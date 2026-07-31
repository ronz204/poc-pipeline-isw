-- Trigger (mantenimiento): un error registrado transiciona la ejecución afectada a 'failed',
-- salvo que ya esté en un estado terminal (evita chocar con trg_executions_validate_transition).
CREATE OR REPLACE FUNCTION trace.fn_execution_errors_fail_execution()
RETURNS trigger AS $$
BEGIN
  UPDATE core.executions
  SET status = 'failed'
  WHERE id = NEW.execution_id
    AND status NOT IN ('completed', 'failed');

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_execution_errors_fail_execution
  AFTER INSERT ON trace.execution_errors
  FOR EACH ROW
  EXECUTE FUNCTION trace.fn_execution_errors_fail_execution();
