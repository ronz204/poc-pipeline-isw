-- Trigger: tasks_validate_swarm_active
-- Table: core.tasks | Event: BEFORE INSERT | Role: validation
--
-- What it does: looks up the referenced swarm's status and deleted_at, and rejects
-- the insert if the swarm is soft-deleted or archived.
--
-- Why it exists: a task represents new work requested from a swarm — creating one
-- against a swarm that's no longer operational (archived) or gone (soft-deleted)
-- would leave orphaned, unactionable work in the system with nothing to execute it.

CREATE OR REPLACE FUNCTION core.fn_tasks_validate_swarm_active()
RETURNS trigger AS $$
DECLARE
  v_swarm_status core.swarm_status;
  v_swarm_deleted_at timestamptz;
BEGIN
  SELECT status, deleted_at INTO v_swarm_status, v_swarm_deleted_at
  FROM core.swarms WHERE id = NEW.swarm_id;

  IF v_swarm_deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Cannot create a task on swarm % (deleted)', NEW.swarm_id
      USING ERRCODE = 'check_violation';
  END IF;

  IF v_swarm_status = 'archived' THEN
    RAISE EXCEPTION 'Cannot create a task on swarm % (archived)', NEW.swarm_id
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_tasks_validate_swarm_active
  BEFORE INSERT ON core.tasks
  FOR EACH ROW
  EXECUTE FUNCTION core.fn_tasks_validate_swarm_active();
