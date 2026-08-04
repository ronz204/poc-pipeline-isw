-- Audit triggers — approach.md §4, independent of the business-rule triggers
-- elsewhere in this folder. All 5 share one function, trace.fn_log_audit_change,
-- defined in drizzle/customs/funcs/audit_change_logger.fn.sql — kept together here
-- since they're one cohesive concept (every INSERT/UPDATE/DELETE on the domain's
-- main entities gets logged, the same way, into trace.audit_log).
--
-- auth.tenants is deliberately not audited here: it's the root of multi-tenant
-- isolation, and no human actor exists yet at the moment a tenant is created.

-- Trigger: audit_swarms
-- Table: core.swarms | Event: AFTER INSERT OR UPDATE OR DELETE | Role: audit
-- Swarms are one of the domain's main entities — every configuration change to one
-- must be attributable to who did it and when.
CREATE TRIGGER trg_audit_swarms
  AFTER INSERT OR UPDATE OR DELETE ON core.swarms
  FOR EACH ROW EXECUTE FUNCTION trace.fn_log_audit_change();

-- Trigger: audit_agents
-- Table: core.agents | Event: AFTER INSERT OR UPDATE OR DELETE | Role: audit
-- Agent configuration (model, tools, role) directly affects what an agent is
-- allowed to do — every change needs to be attributable for the same reason as
-- swarms.
CREATE TRIGGER trg_audit_agents
  AFTER INSERT OR UPDATE OR DELETE ON core.agents
  FOR EACH ROW EXECUTE FUNCTION trace.fn_log_audit_change();

-- Trigger: audit_tasks
-- Table: core.tasks | Event: AFTER INSERT OR UPDATE OR DELETE | Role: audit
-- Same accountability requirement as swarms/agents, applied to the work items
-- themselves.
CREATE TRIGGER trg_audit_tasks
  AFTER INSERT OR UPDATE OR DELETE ON core.tasks
  FOR EACH ROW EXECUTE FUNCTION trace.fn_log_audit_change();

-- Trigger: audit_executions
-- Table: core.executions | Event: AFTER INSERT OR UPDATE OR DELETE | Role: audit
-- Executions are the record of what actually ran — auditing them covers the "what
-- happened, and who's responsible for it" side of that record, separate from the
-- business-rule triggers that also fire on this table.
CREATE TRIGGER trg_audit_executions
  AFTER INSERT OR UPDATE OR DELETE ON core.executions
  FOR EACH ROW EXECUTE FUNCTION trace.fn_log_audit_change();

-- Trigger: audit_users
-- Table: auth.users | Event: AFTER INSERT OR UPDATE OR DELETE | Role: audit
-- This is the human-accountability half of Swampert's auditing (approach.md §4,
-- overview.md) — who created, modified, or removed a user account, as opposed to
-- auditing what the agents themselves did. The password column is stripped from
-- the before/after snapshot for this table only (see the logger function).
CREATE TRIGGER trg_audit_users
  AFTER INSERT OR UPDATE OR DELETE ON auth.users
  FOR EACH ROW EXECUTE FUNCTION trace.fn_log_audit_change();
