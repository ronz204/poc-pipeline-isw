-- Trigger (validación): rechaza crear una tarea sobre un swarm archivado o soft-eliminado.
CREATE OR REPLACE FUNCTION core.fn_tasks_validate_swarm_active()
RETURNS trigger AS $$
DECLARE
  v_swarm_status core.swarm_status;
  v_swarm_deleted_at timestamptz;
BEGIN
  SELECT status, deleted_at INTO v_swarm_status, v_swarm_deleted_at
  FROM core.swarms WHERE id = NEW.swarm_id;

  IF v_swarm_deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'No se puede crear una tarea sobre el swarm % (eliminado)', NEW.swarm_id
      USING ERRCODE = 'check_violation';
  END IF;

  IF v_swarm_status = 'archived' THEN
    RAISE EXCEPTION 'No se puede crear una tarea sobre el swarm % (archivado)', NEW.swarm_id
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_tasks_validate_swarm_active
  BEFORE INSERT ON core.tasks
  FOR EACH ROW
  EXECUTE FUNCTION core.fn_tasks_validate_swarm_active();
