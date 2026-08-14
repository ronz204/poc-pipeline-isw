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
-- Why it exists: launching an attempt by hand means reading the task, checking its
-- swarm, counting existing attempts, inserting the execution and remembering to
-- advance the task's status — five steps that must either all happen or none.
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
