-- Trigger 1 (mantenimiento): completa finished_at cuando status pasa a un estado terminal.
CREATE OR REPLACE FUNCTION core.fn_executions_set_finished_at()
RETURNS trigger AS $$
BEGIN
  IF NEW.status IN ('completed', 'failed') AND NEW.finished_at IS NULL THEN
    NEW.finished_at := now();
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_executions_set_finished_at
  BEFORE UPDATE ON core.executions
  FOR EACH ROW
  EXECUTE FUNCTION core.fn_executions_set_finished_at();

-- Trigger 2 (validación): rechaza transiciones de estado inválidas.
CREATE OR REPLACE FUNCTION core.fn_executions_validate_transition()
RETURNS trigger AS $$
BEGIN
  IF OLD.status IN ('completed', 'failed') AND NEW.status <> OLD.status THEN
    RAISE EXCEPTION 'No se puede transicionar la ejecución % de estado terminal % a %',
      OLD.id, OLD.status, NEW.status
      USING ERRCODE = 'check_violation';
  END IF;

  IF NEW.finished_at IS NOT NULL AND NEW.finished_at < NEW.started_at THEN
    RAISE EXCEPTION 'finished_at (%) no puede ser anterior a started_at (%) en la ejecución %',
      NEW.finished_at, NEW.started_at, NEW.id
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_executions_validate_transition
  BEFORE UPDATE ON core.executions
  FOR EACH ROW
  EXECUTE FUNCTION core.fn_executions_validate_transition();

-- Trigger 3 (validación): rechaza attempt_number no consecutivo para la misma tarea.
CREATE OR REPLACE FUNCTION core.fn_executions_validate_attempt_number()
RETURNS trigger AS $$
DECLARE
  v_expected integer;
BEGIN
  SELECT count(*) + 1 INTO v_expected
  FROM core.executions
  WHERE task_id = NEW.task_id;

  IF NEW.attempt_number <> v_expected THEN
    RAISE EXCEPTION 'attempt_number % inválido para la tarea % (se esperaba %)',
      NEW.attempt_number, NEW.task_id, v_expected
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_executions_validate_attempt_number
  BEFORE INSERT ON core.executions
  FOR EACH ROW
  EXECUTE FUNCTION core.fn_executions_validate_attempt_number();
