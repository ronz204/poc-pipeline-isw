-- Trigger: execution_errors_fail_execution
-- Table: trace.execution_errors | Event: AFTER INSERT | Role: maintenance (derived data)
--
-- What it does: when an error is recorded, flips the referenced execution's status
-- to 'failed' — unless it's already in a terminal state ('completed'/'failed'), in
-- which case the UPDATE simply matches zero rows and nothing happens.
--
-- Why it exists: a recorded error should be reflected in the execution's own status
-- without the caller having to make two separate writes. Skipping already-terminal
-- executions is deliberate — it keeps this trigger from ever fighting
-- trg_executions_validate_transition, which would otherwise reject re-transitioning
-- an execution that already finished. The error itself is still recorded either way;
-- only the status side effect is skipped.

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
