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
-- Why it exists: a step and its cost are one fact recorded in two tables. Written by
-- hand they can drift apart — a step with no cost row (free work that isn't free) or
-- a cost row for a step that was never written. Doing it here also means the budget
-- is checked before anything is written, not discovered afterwards in a report.
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
-- Calling contract: same as the other SECURITY DEFINER procedures in this slice —
-- runs as sampler under FORCE ROW LEVEL SECURITY, so app.current_tenant_id must be
-- set (SET LOCAL is fine) before the call (see core.sp_launch_execution's header).
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
