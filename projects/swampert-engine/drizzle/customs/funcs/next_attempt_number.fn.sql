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
