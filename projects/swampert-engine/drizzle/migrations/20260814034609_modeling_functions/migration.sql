-- Custom SQL migration file --
-- Mirrors, statement for statement, the reusable business functions under
-- drizzle/customs/funcs/ (approach.md §2, 15 pts) — the .fn.sql files only.
-- The two audit functions (trace.fn_log_audit_change, trace.fn_table_history)
-- are NOT repeated here: they're already installed by
-- 20260814032444_modeling_audit, and a second CREATE OR REPLACE FUNCTION for
-- the same routine across two migrations would just be two places to keep in
-- sync for no reason. The .proc.sql files (stored procedures, approach.md §1)
-- are a separate slice, not part of this migration.

-- Function: core.fn_agent_belongs_to_swarm
-- Kind: scalar (boolean)
-- Used by: trace.sp_record_execution_step
--
-- What it does: answers whether a given agent is on a given swarm's roster, i.e.
-- whether the (swarm_id, agent_id) pair exists in core.swarm_agents.
--
-- Why it exists: an execution step is work done by an agent inside a swarm's run —
-- recording a step for an agent that was never assigned to that swarm would produce
-- trace data that contradicts the roster. core.swarm_agents carries no tenant_id and
-- no RLS of its own (trg_swarm_agents_validate_tenant guards it instead), so this
-- lookup is also what keeps a step from silently crossing tenants.
--
-- Example: SELECT core.fn_agent_belongs_to_swarm(
--   '018f0000-0000-7000-8000-00000000000a', '018f0000-0000-7000-8000-000000000001');
CREATE OR REPLACE FUNCTION core.fn_agent_belongs_to_swarm(p_agent_id uuid, p_swarm_id uuid)
RETURNS boolean AS $$
DECLARE
  v_belongs boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM core.swarm_agents sa
    WHERE sa.agent_id = p_agent_id
      AND sa.swarm_id = p_swarm_id
  ) INTO v_belongs;

  RETURN v_belongs;
END;
$$ LANGUAGE plpgsql STABLE;

--> statement-breakpoint
-- Function: trace.fn_calculate_token_cost
-- Kind: scalar (numeric)
-- Used by: trace.sp_record_execution_step
--
-- What it does: pure arithmetic, no table access — turns a token count and a
-- per-1000-token price into the cost of one step:
--   (input_tokens / 1000) * cost_per_1k_input + (output_tokens / 1000) * cost_per_1k_output
-- rounded to 4 decimals, which is the scale trace.token_costs.estimated_cost stores
-- (numeric(10, 4)) — rounding here instead of letting the INSERT truncate keeps the
-- value the procedure checked against the budget identical to the value it writes.
--
-- Why it exists: it's the one place the pricing formula lives. Inlining it in the
-- procedure would mean any future change (a different unit than 1000 tokens, a
-- minimum charge) has to be found and edited wherever a cost is computed.
--
-- Negative inputs are rejected rather than silently producing a negative cost — a
-- negative cost would quietly lower the execution total and defeat the budget check
-- in sp_record_execution_step.
--
-- Example: SELECT trace.fn_calculate_token_cost(480, 210, 0.0010, 0.0030);  -- 0.1110
CREATE OR REPLACE FUNCTION trace.fn_calculate_token_cost(
  p_input_tokens integer,
  p_output_tokens integer,
  p_cost_per_1k_input numeric,
  p_cost_per_1k_output numeric
)
RETURNS numeric AS $$
BEGIN
  IF p_input_tokens IS NULL OR p_output_tokens IS NULL
     OR p_cost_per_1k_input IS NULL OR p_cost_per_1k_output IS NULL THEN
    RAISE EXCEPTION 'fn_calculate_token_cost does not accept NULL arguments'
      USING ERRCODE = 'null_value_not_allowed';
  END IF;

  IF p_input_tokens < 0 OR p_output_tokens < 0
     OR p_cost_per_1k_input < 0 OR p_cost_per_1k_output < 0 THEN
    RAISE EXCEPTION 'Token counts and prices must be non-negative (got %, %, %, %)',
      p_input_tokens, p_output_tokens, p_cost_per_1k_input, p_cost_per_1k_output
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN round(
    (p_input_tokens / 1000.0) * p_cost_per_1k_input
    + (p_output_tokens / 1000.0) * p_cost_per_1k_output,
    4
  );
END;
$$ LANGUAGE plpgsql IMMUTABLE;

--> statement-breakpoint
-- Function: trace.fn_execution_step_summary
-- Kind: table-returning — TABLE(step_number integer, agent_id uuid, tools_used text[], occurred_at timestamptz)
-- Used by: core.sp_complete_execution
--
-- What it does: returns the recorded steps of an execution in the order they
-- happened, without the reasoning payload — the readable trace of a run, not a dump
-- of every column.
--
-- Why it exists: two different needs read the same rows. sp_complete_execution uses
-- an empty result as its "this execution did no work" signal (an execution with zero
-- steps can't be marked completed), and the same query is what a run detail view
-- would show. Soft-deleted steps are excluded, so a retracted step neither shows up
-- in the trace nor keeps an empty execution completable.
--
-- Example: SELECT * FROM trace.fn_execution_step_summary('018f0000-0000-7000-8000-000000000003');
CREATE OR REPLACE FUNCTION trace.fn_execution_step_summary(p_execution_id uuid)
RETURNS TABLE (
  step_number integer,
  agent_id uuid,
  tools_used text[],
  occurred_at timestamptz
) AS $$
BEGIN
  RETURN QUERY
  SELECT s.step_number, s.agent_id, s.tools_used, s.occurred_at
  FROM trace.execution_steps s
  WHERE s.execution_id = p_execution_id
    AND s.deleted_at IS NULL
  ORDER BY s.step_number;
END;
$$ LANGUAGE plpgsql STABLE;

--> statement-breakpoint
-- Function: trace.fn_execution_total_cost
-- Kind: scalar (numeric)
-- Used by: trace.sp_record_execution_step
--
-- What it does: adds up every estimated_cost recorded for an execution so far, and
-- returns 0 (not NULL) for an execution with no cost rows yet, so callers can add to
-- the result without a COALESCE of their own.
--
-- Why it exists: it's the running total the budget check compares against
-- core.fn_tenant_budget_threshold before a new step is written. Soft-deleted cost
-- rows are excluded — a cost that was retracted shouldn't keep consuming budget.
--
-- Example: SELECT trace.fn_execution_total_cost('018f0000-0000-7000-8000-000000000003');
CREATE OR REPLACE FUNCTION trace.fn_execution_total_cost(p_execution_id uuid)
RETURNS numeric AS $$
DECLARE
  v_total numeric;
BEGIN
  SELECT coalesce(sum(tc.estimated_cost), 0) INTO v_total
  FROM trace.token_costs tc
  WHERE tc.execution_id = p_execution_id
    AND tc.deleted_at IS NULL;

  RETURN v_total;
END;
$$ LANGUAGE plpgsql STABLE;

--> statement-breakpoint
-- Function: core.fn_is_swarm_active
-- Kind: scalar (boolean)
-- Used by: core.sp_launch_execution, core.sp_provision_swarm_roster
--
-- What it does: answers whether a swarm is operational right now — status 'active'
-- and not soft-deleted.
--
-- Why it exists: "is this swarm usable?" is the same two-column check in every
-- procedure that touches a swarm. Keeping it in one function means a future change
-- to what "active" means (e.g. treating 'paused' differently) is a one-file change
-- instead of an edit in every caller.
--
-- Example: SELECT core.fn_is_swarm_active('018f0000-0000-7000-8000-000000000001');
CREATE OR REPLACE FUNCTION core.fn_is_swarm_active(p_swarm_id uuid)
RETURNS boolean AS $$
DECLARE
  v_active boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM core.swarms s
    WHERE s.id = p_swarm_id
      AND s.status = 'active'
      AND s.deleted_at IS NULL
  ) INTO v_active;

  RETURN v_active;
END;
$$ LANGUAGE plpgsql STABLE;

--> statement-breakpoint
-- Function: core.fn_next_attempt_number
-- Kind: scalar (integer)
-- Used by: core.sp_launch_execution
--
-- What it does: returns the attempt_number a new execution for the given task must
-- carry — how many executions already exist for that task, plus one.
--
-- Why it exists: sp_launch_execution has to write attempt_number itself, and the
-- value isn't free-form: trg_executions_validate_attempt_number rejects anything
-- that isn't count(*) + 1. This function is the procedure-side counterpart of that
-- rule, so the procedure produces the expected number up front instead of guessing
-- and being rejected by the trigger.
--
-- Note: this deliberately duplicates the count query inside
-- drizzle/customs/triggers/executions_validate_attempt_number.trg.sql — see
-- deltas/process.spec.md § Risks for why the two aren't unified. Both must count the
-- same rows (no deleted_at filter) or the procedure starts failing its own trigger.
--
-- Example: SELECT core.fn_next_attempt_number('018f0000-0000-7000-8000-000000000002');
CREATE OR REPLACE FUNCTION core.fn_next_attempt_number(p_task_id uuid)
RETURNS integer AS $$
DECLARE
  v_next integer;
BEGIN
  SELECT count(*) + 1 INTO v_next
  FROM core.executions e
  WHERE e.task_id = p_task_id;

  RETURN v_next;
END;
$$ LANGUAGE plpgsql STABLE;

--> statement-breakpoint
-- Function: core.fn_stale_swarms
-- Kind: table-returning — TABLE(swarm_id uuid, tenant_id uuid, last_task_at timestamptz)
-- Used by: core.sp_archive_stale_swarms
--
-- What it does: lists every active, non-deleted swarm that has gone quiet — no task
-- created after p_inactive_since, and no execution still pending or running. A swarm
-- that never had a task at all counts as stale and comes back with last_task_at NULL.
--
-- Why it exists: "which swarms are stale?" is a non-trivial read (an aggregate over
-- tasks plus a NOT EXISTS over executions) that the archiving procedure re-runs on
-- every loop iteration. Keeping it as a function means the definition of "stale"
-- lives in one place and can also be queried directly, e.g. to preview what a run of
-- sp_archive_stale_swarms would touch before actually calling it.
--
-- Under FORCE ROW LEVEL SECURITY this only ever returns swarms of the tenant in
-- app.current_tenant_id — it is not a cross-tenant sweep.
--
-- Example: SELECT * FROM core.fn_stale_swarms(now() - interval '90 days');
CREATE OR REPLACE FUNCTION core.fn_stale_swarms(p_inactive_since timestamptz)
RETURNS TABLE (
  swarm_id uuid,
  tenant_id uuid,
  last_task_at timestamptz
) AS $$
BEGIN
  RETURN QUERY
  SELECT s.id, s.tenant_id, max(t.created_at)
  FROM core.swarms s
  LEFT JOIN core.tasks t
    ON t.swarm_id = s.id
   AND t.deleted_at IS NULL
  WHERE s.status = 'active'
    AND s.deleted_at IS NULL
  GROUP BY s.id, s.tenant_id
  HAVING coalesce(max(t.created_at), '-infinity'::timestamptz) < p_inactive_since
     AND NOT EXISTS (
       SELECT 1
       FROM core.executions e
       JOIN core.tasks ot ON ot.id = e.task_id
       WHERE ot.swarm_id = s.id
         AND e.status IN ('pending', 'running')
         AND e.deleted_at IS NULL
     )
  ORDER BY max(t.created_at) NULLS FIRST;
END;
$$ LANGUAGE plpgsql STABLE;

--> statement-breakpoint
-- Function: core.fn_tenant_active_agents
-- Kind: table-returning — TABLE(agent_id uuid, name text, role text)
-- Used by: core.sp_provision_swarm_roster
--
-- What it does: lists every agent a tenant can actually put to work — active and not
-- soft-deleted — ordered by name.
--
-- Why it exists: it's the eligibility list the roster procedure filters against, and
-- the same list a UI would show when picking agents for a swarm. Encapsulating the
-- three conditions (tenant, active, not deleted) keeps "usable agent" from being
-- re-spelled slightly differently at each call site.
--
-- Example: SELECT * FROM core.fn_tenant_active_agents('018f0000-0000-7000-8000-0000000000ff');
CREATE OR REPLACE FUNCTION core.fn_tenant_active_agents(p_tenant_id uuid)
RETURNS TABLE (
  agent_id uuid,
  name text,
  role text
) AS $$
BEGIN
  RETURN QUERY
  SELECT a.id, a.name, a.role
  FROM core.agents a
  WHERE a.tenant_id = p_tenant_id
    AND a.active
    AND a.deleted_at IS NULL
  ORDER BY a.name;
END;
$$ LANGUAGE plpgsql STABLE;

--> statement-breakpoint
-- Function: core.fn_tenant_budget_threshold
-- Kind: scalar (numeric)
-- Used by: trace.sp_record_execution_step
--
-- What it does: returns the maximum accumulated token cost a single execution is
-- allowed to reach, derived from the tenant's plan (auth.tenant_plan).
--
-- Why it exists: the data model is reused from Project I without structural changes,
-- so there is no budget_limit column to read — the ceiling has to come from
-- somewhere, and the plan is the only pricing-related attribute a tenant carries.
-- Keeping it in a function means changing the policy is a CREATE OR REPLACE, not a
-- migration.
--
-- The three amounts below are illustrative placeholders, not calibrated business
-- figures (deltas/process.spec.md § Risks says the same) — don't present them in the
-- oral review as if they came from a real pricing decision.
--
-- Example: SELECT core.fn_tenant_budget_threshold('018f0000-0000-7000-8000-0000000000ff');
CREATE OR REPLACE FUNCTION core.fn_tenant_budget_threshold(p_tenant_id uuid)
RETURNS numeric AS $$
DECLARE
  v_plan auth.tenant_plan;
  v_threshold numeric;
BEGIN
  SELECT t.plan INTO v_plan
  FROM auth.tenants t
  WHERE t.id = p_tenant_id
    AND t.deleted_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Tenant % does not exist or is deleted', p_tenant_id
      USING ERRCODE = 'no_data_found';
  END IF;

  v_threshold := CASE v_plan
    WHEN 'basic'      THEN 50.00
    WHEN 'pro'        THEN 250.00
    WHEN 'enterprise' THEN 1000.00
  END;

  IF v_threshold IS NULL THEN
    RAISE EXCEPTION 'No budget threshold defined for plan %', v_plan
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN v_threshold;
END;
$$ LANGUAGE plpgsql STABLE;
