-- Custom SQL migration file --
-- Mirrors, statement for statement, the 5 canonical business-procedure sources
-- under drizzle/customs/funcs/*.proc.sql — approach.md §1's stored procedures.
-- Does NOT include the DCL these procedures need to run correctly under RLS
-- (FORCE ROW LEVEL SECURITY on the 9 tenant-scoped tables, EXECUTE grants for
-- runner) — that's tracked separately in deltas/process.spec.md § Implementation
-- § Migration, not part of this migration.

-- Procedure: core.sp_launch_execution
-- Tables written: core.executions, core.tasks | Control flow: IF/ELSE
-- Transaction: the two writes live in an inner BEGIN/EXCEPTION block — a real
-- subtransaction that rolls both back if either fails. There is no COMMIT statement:
-- Postgres rejects transaction control inside a SECURITY DEFINER routine with
-- "invalid transaction termination" (verified against Postgres 16), and this
-- procedure has to be SECURITY DEFINER so it can run as sampler. The CALL itself is
-- therefore the commit boundary — all or nothing, which is what the requirement is
-- actually about.
--
-- What it does: starts a new execution attempt for a task. Works out the attempt
-- number itself, inserts the execution as 'pending', and moves the task from
-- 'pending' to 'progress' on its first attempt (a task already in 'progress' from an
-- earlier attempt is left alone).
--
-- Parameters:
--   p_task_id       — task to run. Must exist, not be soft-deleted, not be completed,
--                     and belong to an active swarm.
--   p_max_attempts  — how many attempts this task is allowed in total (default 3).
--                     Launching attempt p_max_attempts + 1 is rejected.
--
-- Calling contract (shared by the four SECURITY DEFINER procedures in this slice):
-- the body runs as sampler with FORCE ROW LEVEL SECURITY applying, so
-- app.current_tenant_id must be set for the tenant's rows to be visible and writable.
-- Setting it with SET LOCAL inside a transaction (what TenantScope.run() does) works
-- here, because this procedure never ends the transaction it was called in.
--
-- Example:
--   SELECT set_config('app.current_tenant_id', '018f0000-0000-7000-8000-0000000000ff', false);
--   CALL core.sp_launch_execution('018f0000-0000-7000-8000-000000000002', 3);
CREATE OR REPLACE PROCEDURE core.sp_launch_execution(
  p_task_id uuid,
  p_max_attempts integer DEFAULT 3
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_tenant_id uuid;
  v_swarm_id uuid;
  v_task_status core.task_status;
  v_task_deleted_at timestamptz;
  v_attempt integer;
BEGIN
  IF p_task_id IS NULL THEN
    RAISE EXCEPTION 'p_task_id is required'
      USING ERRCODE = 'null_value_not_allowed';
  END IF;

  IF p_max_attempts IS NULL OR p_max_attempts < 1 THEN
    RAISE EXCEPTION 'p_max_attempts must be at least 1 (got %)', p_max_attempts
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT t.tenant_id, t.swarm_id, t.status, t.deleted_at
    INTO v_tenant_id, v_swarm_id, v_task_status, v_task_deleted_at
  FROM core.tasks t
  WHERE t.id = p_task_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Task % does not exist', p_task_id
      USING ERRCODE = 'no_data_found';
  END IF;

  IF v_task_deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Cannot launch an execution for task % (deleted)', p_task_id
      USING ERRCODE = 'check_violation';
  END IF;

  IF v_task_status = 'completed' THEN
    RAISE EXCEPTION 'Task % is already completed', p_task_id
      USING ERRCODE = 'check_violation';
  END IF;

  IF NOT core.fn_is_swarm_active(v_swarm_id) THEN
    RAISE EXCEPTION 'Cannot launch an execution for task %: swarm % is not active',
      p_task_id, v_swarm_id
      USING ERRCODE = 'check_violation';
  END IF;

  v_attempt := core.fn_next_attempt_number(p_task_id);

  IF v_attempt > p_max_attempts THEN
    RAISE EXCEPTION 'Task % already used its % allowed attempts', p_task_id, p_max_attempts
      USING ERRCODE = 'check_violation';
  END IF;

  -- Both writes belong to the same unit of work: an execution row that exists while
  -- its task stayed 'pending' would be a task nothing shows as running. The inner
  -- block is a subtransaction — an error in either statement rolls back both before
  -- the re-raise below reaches the caller.
  BEGIN
    INSERT INTO core.executions (id, tenant_id, task_id, attempt_number, status, started_at)
    VALUES (extensions.gen_random_uuid(), v_tenant_id, p_task_id, v_attempt, 'pending', now());

    IF v_task_status = 'pending' THEN
      UPDATE core.tasks SET status = 'progress' WHERE id = p_task_id;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'sp_launch_execution rolled back for task % (attempt %): %',
      p_task_id, v_attempt, SQLERRM
      USING ERRCODE = SQLSTATE;
  END;
END;
$$;

--> statement-breakpoint
-- Procedure: core.sp_complete_execution
-- Tables written: core.executions, core.tasks (plus a retry attempt via
-- core.sp_launch_execution) | Control flow: CASE, IF/ELSE
-- Transaction: closing the execution, updating the task and launching the retry all
-- happen inside one inner BEGIN/EXCEPTION block — a subtransaction that rolls the
-- whole decision back if any part of it fails. No COMMIT statement: Postgres rejects
-- transaction control inside SECURITY DEFINER routines (see
-- core.sp_launch_execution's header), so the CALL is the commit boundary.
--
-- What it does: closes an execution and decides what that means for its task.
-- Completing marks the task completed. Failing consumes an attempt: while attempts
-- remain, a fresh attempt is launched automatically; once they're exhausted, the task
-- itself is marked failed.
--
-- Parameters:
--   p_execution_id  — execution to close. Must exist, not be soft-deleted, and not
--                     already be in a terminal status.
--   p_status        — 'completed' or 'failed'. Any other execution_status value is
--                     rejected: 'pending'/'running' are not ways to close a run.
--   p_max_attempts  — attempt budget for the task (default 3), same meaning as in
--                     sp_launch_execution.
--
-- Completing requires at least one recorded step (trace.fn_execution_step_summary
-- returning nothing means nothing was actually done) — an execution can't be declared
-- successful with no trace of work behind it.
--
-- Example:
--   SELECT set_config('app.current_tenant_id', '018f0000-0000-7000-8000-0000000000ff', false);
--   CALL core.sp_complete_execution('018f0000-0000-7000-8000-000000000003', 'failed', 3);
CREATE OR REPLACE PROCEDURE core.sp_complete_execution(
  p_execution_id uuid,
  p_status core.execution_status,
  p_max_attempts integer DEFAULT 3
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_task_id uuid;
  v_attempt integer;
  v_current_status core.execution_status;
  v_execution_deleted_at timestamptz;
  v_step_count integer;
BEGIN
  IF p_execution_id IS NULL THEN
    RAISE EXCEPTION 'p_execution_id is required'
      USING ERRCODE = 'null_value_not_allowed';
  END IF;

  IF p_status IS NULL OR p_status NOT IN ('completed', 'failed') THEN
    RAISE EXCEPTION 'p_status must be ''completed'' or ''failed'' (got %)', p_status
      USING ERRCODE = 'check_violation';
  END IF;

  IF p_max_attempts IS NULL OR p_max_attempts < 1 THEN
    RAISE EXCEPTION 'p_max_attempts must be at least 1 (got %)', p_max_attempts
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT e.task_id, e.attempt_number, e.status, e.deleted_at
    INTO v_task_id, v_attempt, v_current_status, v_execution_deleted_at
  FROM core.executions e
  WHERE e.id = p_execution_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Execution % does not exist', p_execution_id
      USING ERRCODE = 'no_data_found';
  END IF;

  IF v_execution_deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Cannot close execution % (deleted)', p_execution_id
      USING ERRCODE = 'check_violation';
  END IF;

  -- trg_executions_validate_transition would reject this too; catching it here gives
  -- the caller a procedure-level message instead of a trigger-level one.
  IF v_current_status IN ('completed', 'failed') THEN
    RAISE EXCEPTION 'Execution % is already in terminal status %',
      p_execution_id, v_current_status
      USING ERRCODE = 'check_violation';
  END IF;

  IF p_status = 'completed' THEN
    SELECT count(*) INTO v_step_count
    FROM trace.fn_execution_step_summary(p_execution_id);

    IF v_step_count = 0 THEN
      RAISE EXCEPTION 'Execution % cannot be completed: no steps were recorded',
        p_execution_id
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  BEGIN
    UPDATE core.executions
    SET status = p_status,
        finished_at = now()
    WHERE id = p_execution_id;

    CASE p_status
      WHEN 'completed' THEN
        UPDATE core.tasks SET status = 'completed' WHERE id = v_task_id;

      WHEN 'failed' THEN
        IF v_attempt < p_max_attempts THEN
          -- Attempts left: the next one starts on its own. The task keeps its
          -- current status ('progress'), which is what sp_launch_execution expects.
          CALL core.sp_launch_execution(v_task_id, p_max_attempts);
        ELSE
          UPDATE core.tasks SET status = 'failed' WHERE id = v_task_id;
        END IF;

      ELSE
        RAISE EXCEPTION 'Unsupported closing status %', p_status
          USING ERRCODE = 'check_violation';
    END CASE;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'sp_complete_execution rolled back for execution % (status %): %',
      p_execution_id, p_status, SQLERRM
      USING ERRCODE = SQLSTATE;
  END;
END;
$$;

--> statement-breakpoint
-- Procedure: trace.sp_record_execution_step
-- Tables written: trace.execution_steps, trace.token_costs | Control flow: IF
-- Transaction: both inserts live in an inner BEGIN/EXCEPTION block — a subtransaction
-- that rolls the step back if the cost insert fails, and vice versa. No COMMIT
-- statement: Postgres rejects transaction control inside SECURITY DEFINER routines
-- (see core.sp_launch_execution's header), so the CALL is the commit boundary.
--
-- What it does: records one step of a run together with what it cost. Works out the
-- step's position in the run itself, prices the tokens, and refuses the whole call if
-- the execution's accumulated cost would cross the tenant's plan budget.
--
-- Parameters:
--   p_execution_id        — run this step belongs to. Must exist and not be terminal
--                           or soft-deleted; a finished run doesn't grow new steps.
--   p_agent_id            — agent that did the work. Must be on the roster of the
--                           swarm the execution's task belongs to.
--   p_reasoning           — jsonb payload describing what the agent reasoned. NULL is
--                           accepted and stored as '{}'.
--   p_tools_used          — tools the agent invoked. NULL is accepted and stored as
--                           an empty array.
--   p_input_tokens        — tokens sent, non-negative.
--   p_output_tokens       — tokens produced, non-negative.
--   p_cost_per_1k_input   — price per 1000 input tokens, non-negative.
--   p_cost_per_1k_output  — price per 1000 output tokens, non-negative.
--
-- step_number is derived (max + 1 within the execution), not received: a caller
-- passing it would be able to create gaps or duplicates in a run's trace.
--
-- Example:
--   SELECT set_config('app.current_tenant_id', '018f0000-0000-7000-8000-0000000000ff', false);
--   CALL trace.sp_record_execution_step(
--     '018f0000-0000-7000-8000-000000000003',
--     '018f0000-0000-7000-8000-00000000000a',
--     '{"summary":"searched the docs"}'::jsonb,
--     ARRAY['web_search'],
--     480, 210, 0.0010, 0.0030);
CREATE OR REPLACE PROCEDURE trace.sp_record_execution_step(
  p_execution_id uuid,
  p_agent_id uuid,
  p_reasoning jsonb,
  p_tools_used text[],
  p_input_tokens integer,
  p_output_tokens integer,
  p_cost_per_1k_input numeric,
  p_cost_per_1k_output numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_tenant_id uuid;
  v_swarm_id uuid;
  v_execution_status core.execution_status;
  v_execution_deleted_at timestamptz;
  v_step_number integer;
  v_step_id uuid;
  v_cost numeric;
  v_total numeric;
  v_threshold numeric;
BEGIN
  IF p_execution_id IS NULL OR p_agent_id IS NULL THEN
    RAISE EXCEPTION 'p_execution_id and p_agent_id are required'
      USING ERRCODE = 'null_value_not_allowed';
  END IF;

  -- execution → task → swarm in one join: a single hop each way doesn't earn its own
  -- reusable function (deltas/process.spec.md § Implementation).
  SELECT e.tenant_id, t.swarm_id, e.status, e.deleted_at
    INTO v_tenant_id, v_swarm_id, v_execution_status, v_execution_deleted_at
  FROM core.executions e
  JOIN core.tasks t ON t.id = e.task_id
  WHERE e.id = p_execution_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Execution % does not exist', p_execution_id
      USING ERRCODE = 'no_data_found';
  END IF;

  IF v_execution_deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Cannot record a step on execution % (deleted)', p_execution_id
      USING ERRCODE = 'check_violation';
  END IF;

  IF v_execution_status IN ('completed', 'failed') THEN
    RAISE EXCEPTION 'Cannot record a step on execution %: already in terminal status %',
      p_execution_id, v_execution_status
      USING ERRCODE = 'check_violation';
  END IF;

  IF NOT core.fn_agent_belongs_to_swarm(p_agent_id, v_swarm_id) THEN
    RAISE EXCEPTION 'Agent % is not on the roster of swarm %', p_agent_id, v_swarm_id
      USING ERRCODE = 'check_violation';
  END IF;

  -- fn_calculate_token_cost rejects negative tokens/prices on its own.
  v_cost := trace.fn_calculate_token_cost(
    p_input_tokens, p_output_tokens, p_cost_per_1k_input, p_cost_per_1k_output);

  v_total := trace.fn_execution_total_cost(p_execution_id);
  v_threshold := core.fn_tenant_budget_threshold(v_tenant_id);

  IF v_total + v_cost > v_threshold THEN
    RAISE EXCEPTION 'Execution % would reach %, over the tenant budget of % (step costs %)',
      p_execution_id, v_total + v_cost, v_threshold, v_cost
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT coalesce(max(s.step_number), 0) + 1 INTO v_step_number
  FROM trace.execution_steps s
  WHERE s.execution_id = p_execution_id;

  v_step_id := extensions.gen_random_uuid();

  BEGIN
    INSERT INTO trace.execution_steps (
      id, tenant_id, execution_id, agent_id, step_number, reasoning, tools_used, occurred_at)
    VALUES (
      v_step_id, v_tenant_id, p_execution_id, p_agent_id, v_step_number,
      coalesce(p_reasoning, '{}'::jsonb), coalesce(p_tools_used, ARRAY[]::text[]), now());

    INSERT INTO trace.token_costs (
      id, tenant_id, execution_id, step_id, input_tokens, output_tokens, estimated_cost, recorded_at)
    VALUES (
      extensions.gen_random_uuid(), v_tenant_id, p_execution_id, v_step_id,
      p_input_tokens, p_output_tokens, v_cost, now());
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'sp_record_execution_step rolled back for execution % (step %): %',
      p_execution_id, v_step_number, SQLERRM
      USING ERRCODE = SQLSTATE;
  END;
END;
$$;

--> statement-breakpoint
-- Procedure: core.sp_provision_swarm_roster
-- Tables written: core.swarm_agents | Control flow: FOR
-- Transaction: none of its own — a single table is written, so the surrounding
-- transaction is already the whole unit of work (approach.md §1 asks for explicit
-- transactions when a procedure modifies more than one table).
--
-- What it does: assigns a batch of agents to a swarm in one call. Every id that isn't
-- an active agent of the swarm's own tenant is skipped, as is every id already on the
-- roster, so the same call can be repeated to top up a roster without failing on what
-- is already there.
--
-- Parameters:
--   p_swarm_id   — swarm to staff. Must exist, be active and not soft-deleted.
--   p_agent_ids  — agent ids to add. Must contain at least one element; individual
--                  ids that don't qualify are skipped, not rejected.
--
-- Note: skipping instead of raising is deliberate and it is the one place in this
-- slice where invalid input doesn't fail the call — a batch that is half-valid still
-- staffs what it can. The NOTICE reports the split; nothing else signals it (see
-- deltas/process.spec.md § Risks).
--
-- Example:
--   SELECT set_config('app.current_tenant_id', '018f0000-0000-7000-8000-0000000000ff', false);
--   CALL core.sp_provision_swarm_roster(
--     '018f0000-0000-7000-8000-000000000001',
--     ARRAY['018f0000-0000-7000-8000-00000000000a',
--           '018f0000-0000-7000-8000-00000000000b']::uuid[]);
CREATE OR REPLACE PROCEDURE core.sp_provision_swarm_roster(
  p_swarm_id uuid,
  p_agent_ids uuid[]
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_tenant_id uuid;
  v_swarm_deleted_at timestamptz;
  v_agent_id uuid;
  v_added integer := 0;
  v_skipped integer := 0;
BEGIN
  IF p_swarm_id IS NULL THEN
    RAISE EXCEPTION 'p_swarm_id is required'
      USING ERRCODE = 'null_value_not_allowed';
  END IF;

  IF p_agent_ids IS NULL OR array_length(p_agent_ids, 1) IS NULL THEN
    RAISE EXCEPTION 'p_agent_ids must contain at least one agent id'
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT s.tenant_id, s.deleted_at
    INTO v_tenant_id, v_swarm_deleted_at
  FROM core.swarms s
  WHERE s.id = p_swarm_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Swarm % does not exist', p_swarm_id
      USING ERRCODE = 'no_data_found';
  END IF;

  IF v_swarm_deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Cannot staff swarm % (deleted)', p_swarm_id
      USING ERRCODE = 'check_violation';
  END IF;

  IF NOT core.fn_is_swarm_active(p_swarm_id) THEN
    RAISE EXCEPTION 'Cannot staff swarm %: it is not active', p_swarm_id
      USING ERRCODE = 'check_violation';
  END IF;

  FOR v_agent_id IN SELECT unnest(p_agent_ids)
  LOOP
    -- Not an active agent of this swarm's tenant. trg_swarm_agents_validate_tenant
    -- would reject a cross-tenant pair anyway; filtering here is what turns that
    -- rejection into a skip, so one foreign id doesn't abort the whole batch.
    IF NOT EXISTS (
      SELECT 1
      FROM core.fn_tenant_active_agents(v_tenant_id) a
      WHERE a.agent_id = v_agent_id
    ) THEN
      v_skipped := v_skipped + 1;
      CONTINUE;
    END IF;

    IF EXISTS (
      SELECT 1
      FROM core.swarm_agents sa
      WHERE sa.swarm_id = p_swarm_id
        AND sa.agent_id = v_agent_id
    ) THEN
      v_skipped := v_skipped + 1;
      CONTINUE;
    END IF;

    INSERT INTO core.swarm_agents (swarm_id, agent_id, added_at)
    VALUES (p_swarm_id, v_agent_id, now());

    v_added := v_added + 1;
  END LOOP;

  RAISE NOTICE 'Swarm %: % agent(s) added, % skipped', p_swarm_id, v_added, v_skipped;
END;
$$;

--> statement-breakpoint
-- Procedure: core.sp_archive_stale_swarms
-- Tables written: core.swarms, core.tasks | Control flow: WHILE
-- Transaction: explicit — one COMMIT per swarm, inside the loop. This is the only
-- procedure in this slice that commits mid-run, and the reason it is a PROCEDURE and
-- not a FUNCTION: a function cannot control transactions in Postgres.
--
-- It is also the only one that is NOT SECURITY DEFINER, and that is forced, not a
-- preference: Postgres raises "invalid transaction termination" on a COMMIT inside a
-- SECURITY DEFINER routine (verified against Postgres 16), so a procedure cannot both
-- run as the owner and commit per iteration. Committing per swarm is this procedure's
-- whole point, so it runs as the caller instead — which today is runner, and runner
-- already holds direct UPDATE on core.swarms/core.tasks (database.md § Postgres
-- roles). If runner's direct table privileges are ever revoked, this procedure needs
-- its own GRANT on those two tables — the other four keep working untouched.
--
-- What it does: batch job. Takes every swarm core.fn_stale_swarms reports as quiet,
-- archives it, and fails the tasks it left open ('pending'/'progress'), one swarm at
-- a time, committing each before moving on.
--
-- Parameters:
--   p_inactive_since  — cutoff timestamp. A swarm counts as stale when it has no task
--                       created after this moment and no pending/running execution.
--                       Must not be in the future — that would archive everything.
--
-- The loop re-runs fn_stale_swarms each iteration instead of holding a cursor open:
-- a cursor is closed by the COMMIT, and re-querying is safe precisely because an
-- archived swarm no longer matches (fn_stale_swarms only looks at active ones). The
-- ROW_COUNT guard below is what keeps that from becoming an infinite loop if an
-- UPDATE ever matches nothing (missing tenant context under FORCE RLS is the
-- realistic way that happens).
--
-- Scope note: under RLS this archives only the swarms of the tenant in
-- app.current_tenant_id, so it is a per-tenant job, not a global sweep.
--
-- Calling contract: must be called outside a client-opened transaction, with the
-- tenant set at session level — the COMMITs below would otherwise discard a
-- transaction-local setting halfway through the run (see core.sp_launch_execution's
-- header). The value is re-applied after each COMMIT for exactly that reason.
--
-- Example:
--   SELECT set_config('app.current_tenant_id', '018f0000-0000-7000-8000-0000000000ff', false);
--   CALL core.sp_archive_stale_swarms(now() - interval '90 days');
CREATE OR REPLACE PROCEDURE core.sp_archive_stale_swarms(p_inactive_since timestamptz)
LANGUAGE plpgsql
AS $$
DECLARE
  v_swarm_id uuid;
  v_last_task_at timestamptz;
  v_has_stale boolean;
  v_archived_swarms integer := 0;
  v_failed_tasks integer := 0;
  v_row_count integer;
  v_tenant_ctx text;
BEGIN
  IF p_inactive_since IS NULL THEN
    RAISE EXCEPTION 'p_inactive_since is required'
      USING ERRCODE = 'null_value_not_allowed';
  END IF;

  IF p_inactive_since > now() THEN
    RAISE EXCEPTION 'p_inactive_since (%) is in the future: that would archive every active swarm',
      p_inactive_since
      USING ERRCODE = 'check_violation';
  END IF;

  v_tenant_ctx := NULLIF(current_setting('app.current_tenant_id', true), '');

  SELECT s.swarm_id, s.last_task_at
    INTO v_swarm_id, v_last_task_at
  FROM core.fn_stale_swarms(p_inactive_since) s
  LIMIT 1;

  v_has_stale := FOUND;

  WHILE v_has_stale
  LOOP
    UPDATE core.swarms
    SET status = 'archived'
    WHERE id = v_swarm_id;

    GET DIAGNOSTICS v_row_count = ROW_COUNT;

    IF v_row_count = 0 THEN
      RAISE EXCEPTION 'Swarm % is stale but could not be archived — is app.current_tenant_id set?',
        v_swarm_id
        USING ERRCODE = 'check_violation';
    END IF;

    UPDATE core.tasks
    SET status = 'failed'
    WHERE swarm_id = v_swarm_id
      AND status IN ('pending', 'progress')
      AND deleted_at IS NULL;

    GET DIAGNOSTICS v_row_count = ROW_COUNT;
    v_failed_tasks := v_failed_tasks + v_row_count;
    v_archived_swarms := v_archived_swarms + 1;

    RAISE NOTICE 'Archived swarm % (last task at %), % open task(s) failed',
      v_swarm_id, v_last_task_at, v_row_count;

    -- Each swarm is independent: committing here is what makes an interrupted run
    -- leave finished swarms archived instead of undoing the whole batch.
    COMMIT;

    IF v_tenant_ctx IS NOT NULL THEN
      PERFORM set_config('app.current_tenant_id', v_tenant_ctx, false);
    END IF;

    SELECT s.swarm_id, s.last_task_at
      INTO v_swarm_id, v_last_task_at
    FROM core.fn_stale_swarms(p_inactive_since) s
    LIMIT 1;

    v_has_stale := FOUND;
  END LOOP;

  RAISE NOTICE 'Done: % swarm(s) archived, % task(s) failed', v_archived_swarms, v_failed_tasks;
END;
$$;
