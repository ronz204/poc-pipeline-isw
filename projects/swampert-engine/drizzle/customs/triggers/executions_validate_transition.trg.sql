-- Trigger: executions_validate_transition
-- Table: core.executions | Event: BEFORE UPDATE | Role: validation
--
-- What it does: rejects two kinds of invalid update on an execution —
--   1. Changing status away from a terminal state ('completed'/'failed') to
--      anything else. Terminal states are final; an execution can't be reopened.
--   2. Setting finished_at earlier than started_at.
--
-- Why it exists: without this, a bug or a manual UPDATE could silently put an
-- execution back into a non-terminal state after it already finished, or leave a
-- finished_at/started_at pair that makes no chronological sense — either would
-- corrupt any report or dashboard built on top of execution timing.

CREATE OR REPLACE FUNCTION core.fn_executions_validate_transition()
RETURNS trigger AS $$
BEGIN
  IF OLD.status IN ('completed', 'failed') AND NEW.status <> OLD.status THEN
    RAISE EXCEPTION 'Execution % cannot transition from terminal status % to %',
      OLD.id, OLD.status, NEW.status
      USING ERRCODE = 'check_violation';
  END IF;

  IF NEW.finished_at IS NOT NULL AND NEW.finished_at < NEW.started_at THEN
    RAISE EXCEPTION 'finished_at (%) cannot be earlier than started_at (%) on execution %',
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
