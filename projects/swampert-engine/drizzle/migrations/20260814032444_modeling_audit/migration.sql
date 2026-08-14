-- Custom SQL migration file --
-- Mirrors, statement for statement, the canonical sources under
-- drizzle/customs/funcs/audit_change_logger.fn.sql,
-- drizzle/customs/funcs/audit_table_history.fn.sql, and
-- drizzle/customs/triggers/audit_log_changes.trg.sql — approach.md §4's
-- audit system, independent of the business-rule triggers modeled elsewhere.

-- Function: trace.fn_log_audit_change
-- Used by: every trigger below (trg_audit_swarms, trg_audit_agents,
--          trg_audit_tasks, trg_audit_executions, trg_audit_users)
--
-- What it does: on every INSERT/UPDATE/DELETE of an audited table, inserts one row
-- into trace.audit_log recording the tenant, the resolved actor, the action, the
-- entity, a readable one-line summary, and a before/after JSON snapshot (with
-- 'password' stripped, since auth.users is the only audited table that has one).
--
-- Actor resolution: current_setting('app.current_user_id', true) is used when the
-- caller set it via TenantScope.setActor(). If it's NULL:
--   - A brand-new auth.users row audits itself (NEW.id) — a user that was just
--     created has no app.current_user_id of their own yet.
--   - Otherwise, falls back to the affected tenant's admin user, or its oldest user
--     if it has none — the same criterion the seeder already uses. This keeps an
--     audited write from failing on audit_log.user_id's NOT NULL constraint just
--     because a call site forgot to set an actor.
CREATE OR REPLACE FUNCTION trace.fn_log_audit_change()
RETURNS trigger AS $$
DECLARE
  v_actor uuid;
  v_entity_id uuid;
  v_tenant_id uuid;
  v_action text;
  v_summary text;
BEGIN
  v_actor := NULLIF(current_setting('app.current_user_id', true), '')::uuid;

  IF TG_OP = 'DELETE' THEN
    v_entity_id := OLD.id;
    v_tenant_id := OLD.tenant_id;
    v_action := 'deleted';
    v_summary := format('%s deleted (id=%s)', TG_TABLE_NAME, OLD.id);
  ELSIF TG_OP = 'UPDATE' THEN
    v_entity_id := NEW.id;
    v_tenant_id := NEW.tenant_id;
    v_action := 'updated';
    v_summary := format('%s updated (id=%s)', TG_TABLE_NAME, NEW.id);
  ELSE
    v_entity_id := NEW.id;
    v_tenant_id := NEW.tenant_id;
    v_action := 'created';
    v_summary := format('%s created (id=%s)', TG_TABLE_NAME, NEW.id);
  END IF;

  IF v_actor IS NULL THEN
    -- A freshly created user has no app.current_user_id set yet (that happens
    -- after creation, see TenantScope.setActor) — it audits itself instead.
    IF TG_TABLE_NAME = 'users' AND TG_OP = 'INSERT' THEN
      v_actor := NEW.id;
    ELSE
      -- No actor set on the session (a call site skipped TenantScope.setActor) —
      -- fall back to the tenant's admin, or its oldest user if there's no admin.
      SELECT id INTO v_actor
      FROM auth.users
      WHERE tenant_id = v_tenant_id
      ORDER BY (role = 'admin') DESC, created_at ASC
      LIMIT 1;
    END IF;
  END IF;

  INSERT INTO trace.audit_log (id, tenant_id, user_id, action, entity_type, entity_id, details, occurred_at)
  VALUES (
    extensions.gen_random_uuid(),
    v_tenant_id,
    v_actor,
    v_action,
    TG_TABLE_NAME,
    v_entity_id,
    jsonb_build_object(
      'summary', v_summary,
      -- password (auth.users) never ends up in the audit trail, not even hashed.
      'before', to_jsonb(OLD) - 'password',
      'after', to_jsonb(NEW) - 'password'
    ),
    now()
  );

  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

--> statement-breakpoint
-- Function: trace.fn_table_history
-- Role: query function (not a trigger) — reads what the audit triggers below wrote.
--
-- What it does: returns every trace.audit_log row recorded for a given table name,
-- most recent first.
--
-- Why it exists: this is the query counterpart approach.md §4 asks for (referred to
-- there as "ver_historial_tabla(nombre_tabla)") — one place to look up a table's
-- full change history instead of every caller writing its own audit_log query.
CREATE OR REPLACE FUNCTION trace.fn_table_history(p_table_name text)
RETURNS TABLE (
  id uuid,
  user_id uuid,
  action text,
  entity_id uuid,
  details jsonb,
  occurred_at timestamptz
) AS $$
BEGIN
  RETURN QUERY
  SELECT a.id, a.user_id, a.action, a.entity_id, a.details, a.occurred_at
  FROM trace.audit_log a
  WHERE a.entity_type = p_table_name
  ORDER BY a.occurred_at DESC;
END;
$$ LANGUAGE plpgsql;

--> statement-breakpoint
-- Trigger: audit_swarms
-- Table: core.swarms | Event: AFTER INSERT OR UPDATE OR DELETE | Role: audit
-- Swarms are one of the domain's main entities — every configuration change to one
-- must be attributable to who did it and when.
CREATE TRIGGER trg_audit_swarms
  AFTER INSERT OR UPDATE OR DELETE ON core.swarms
  FOR EACH ROW EXECUTE FUNCTION trace.fn_log_audit_change();

--> statement-breakpoint
-- Trigger: audit_agents
-- Table: core.agents | Event: AFTER INSERT OR UPDATE OR DELETE | Role: audit
-- Agent configuration (model, tools, role) directly affects what an agent is
-- allowed to do — every change needs to be attributable for the same reason as
-- swarms.
CREATE TRIGGER trg_audit_agents
  AFTER INSERT OR UPDATE OR DELETE ON core.agents
  FOR EACH ROW EXECUTE FUNCTION trace.fn_log_audit_change();

--> statement-breakpoint
-- Trigger: audit_tasks
-- Table: core.tasks | Event: AFTER INSERT OR UPDATE OR DELETE | Role: audit
-- Same accountability requirement as swarms/agents, applied to the work items
-- themselves.
CREATE TRIGGER trg_audit_tasks
  AFTER INSERT OR UPDATE OR DELETE ON core.tasks
  FOR EACH ROW EXECUTE FUNCTION trace.fn_log_audit_change();

--> statement-breakpoint
-- Trigger: audit_executions
-- Table: core.executions | Event: AFTER INSERT OR UPDATE OR DELETE | Role: audit
-- Executions are the record of what actually ran — auditing them covers the "what
-- happened, and who's responsible for it" side of that record, separate from the
-- business-rule triggers that also fire on this table.
CREATE TRIGGER trg_audit_executions
  AFTER INSERT OR UPDATE OR DELETE ON core.executions
  FOR EACH ROW EXECUTE FUNCTION trace.fn_log_audit_change();

--> statement-breakpoint
-- Trigger: audit_users
-- Table: auth.users | Event: AFTER INSERT OR UPDATE OR DELETE | Role: audit
-- This is the human-accountability half of Swampert's auditing (approach.md §4,
-- overview.md) — who created, modified, or removed a user account, as opposed to
-- auditing what the agents themselves did. The password column is stripped from
-- the before/after snapshot for this table only (see the logger function).
CREATE TRIGGER trg_audit_users
  AFTER INSERT OR UPDATE OR DELETE ON auth.users
  FOR EACH ROW EXECUTE FUNCTION trace.fn_log_audit_change();
