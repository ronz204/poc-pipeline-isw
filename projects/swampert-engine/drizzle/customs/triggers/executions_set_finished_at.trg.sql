-- Trigger: executions_set_finished_at
-- Table: core.executions | Event: BEFORE UPDATE | Role: maintenance (derived data)
--
-- What it does: stamps finished_at with now() the moment status reaches a terminal
-- value ('completed' or 'failed'), if it hasn't been set already.
--
-- Why it exists: finished_at is a derived timestamp, not something a caller should
-- have to remember to set on every terminal transition. Deriving it here keeps it
-- always consistent with the status change that caused it, instead of depending on
-- every write path getting it right independently.

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
