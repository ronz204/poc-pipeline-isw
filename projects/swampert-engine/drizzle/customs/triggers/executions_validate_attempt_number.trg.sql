-- Trigger: executions_validate_attempt_number
-- Table: core.executions | Event: BEFORE INSERT | Role: validation
--
-- What it does: counts how many executions already exist for the same task_id and
-- rejects the insert unless attempt_number equals that count + 1.
--
-- Why it exists: attempt_number is what makes retries orderable and countable —
-- without this check, a caller could insert attempt numbers out of order or with
-- gaps/duplicates, breaking any logic that assumes a task's attempts are strictly
-- consecutive (1, 2, 3, ...).

CREATE OR REPLACE FUNCTION core.fn_executions_validate_attempt_number()
RETURNS trigger AS $$
DECLARE
  v_expected integer;
BEGIN
  SELECT count(*) + 1 INTO v_expected
  FROM core.executions
  WHERE task_id = NEW.task_id;

  IF NEW.attempt_number <> v_expected THEN
    RAISE EXCEPTION 'Invalid attempt_number % for task % (expected %)',
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
