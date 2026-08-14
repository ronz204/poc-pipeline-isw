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
-- Why it exists: this is the retry policy of the whole system in one place. Done by
-- hand it's "update the execution, then remember what the failure implies" — the part
-- everyone forgets, leaving tasks stuck in 'progress' with no execution running.
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
-- Note: on 'failed' with attempts left, the caller gets a side effect it didn't ask
-- for — a new execution row. That's the intended retry policy, not an accident; see
-- deltas/process.spec.md § Risks. Because the retry shares this call's transaction,
-- a retry that can't launch (its swarm was archived meanwhile) fails the whole call
-- and leaves the execution open, rather than closing it with the retry silently
-- skipped — the failure is surfaced instead of swallowed.
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
