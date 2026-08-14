-- Custom SQL migration file --
-- Mirrors, statement for statement, the 6 canonical business-trigger sources under
-- drizzle/customs/triggers/ — approach.md §3's business-rule triggers, independent
-- of the audit system installed in 20260814032444_modeling_audit.

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

--> statement-breakpoint
CREATE TRIGGER trg_executions_validate_transition
  BEFORE UPDATE ON core.executions
  FOR EACH ROW
  EXECUTE FUNCTION core.fn_executions_validate_transition();

--> statement-breakpoint
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

--> statement-breakpoint
CREATE TRIGGER trg_executions_validate_attempt_number
  BEFORE INSERT ON core.executions
  FOR EACH ROW
  EXECUTE FUNCTION core.fn_executions_validate_attempt_number();

--> statement-breakpoint
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

--> statement-breakpoint
CREATE TRIGGER trg_executions_set_finished_at
  BEFORE UPDATE ON core.executions
  FOR EACH ROW
  EXECUTE FUNCTION core.fn_executions_set_finished_at();

--> statement-breakpoint
-- Trigger: swarm_agents_validate_tenant
-- Table: core.swarm_agents | Event: BEFORE INSERT | Role: validation
--
-- What it does: looks up the tenant_id of the referenced swarm and the referenced
-- agent, and rejects the insert if they differ.
--
-- Why it exists: swarm_agents is a pure junction table — it carries no tenant_id of
-- its own and has no RLS policy. Without this trigger, nothing at the database level
-- would stop a swarm from one tenant being linked to an agent from another, which
-- would be a real cross-tenant data leak. This trigger closes that isolation gap at
-- the integrity level, since RLS can't cover a table that has no tenant_id column to
-- filter on.
CREATE OR REPLACE FUNCTION core.fn_swarm_agents_validate_tenant()
RETURNS trigger AS $$
DECLARE
  v_swarm_tenant uuid;
  v_agent_tenant uuid;
BEGIN
  SELECT tenant_id INTO v_swarm_tenant FROM core.swarms WHERE id = NEW.swarm_id;
  SELECT tenant_id INTO v_agent_tenant FROM core.agents WHERE id = NEW.agent_id;

  IF v_swarm_tenant IS DISTINCT FROM v_agent_tenant THEN
    RAISE EXCEPTION 'Swarm % (tenant %) and agent % (tenant %) belong to different tenants',
      NEW.swarm_id, v_swarm_tenant, NEW.agent_id, v_agent_tenant
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

--> statement-breakpoint
CREATE TRIGGER trg_swarm_agents_validate_tenant
  BEFORE INSERT ON core.swarm_agents
  FOR EACH ROW
  EXECUTE FUNCTION core.fn_swarm_agents_validate_tenant();

--> statement-breakpoint
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

--> statement-breakpoint
CREATE TRIGGER trg_tasks_validate_swarm_active
  BEFORE INSERT ON core.tasks
  FOR EACH ROW
  EXECUTE FUNCTION core.fn_tasks_validate_swarm_active();

--> statement-breakpoint
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

--> statement-breakpoint
CREATE TRIGGER trg_execution_errors_fail_execution
  AFTER INSERT ON trace.execution_errors
  FOR EACH ROW
  EXECUTE FUNCTION trace.fn_execution_errors_fail_execution();
