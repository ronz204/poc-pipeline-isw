-- Function: trace.fn_log_audit_change
-- Used by: every trigger in drizzle/customs/triggers/audit_log_changes.trg.sql (trg_audit_swarms,
--          trg_audit_agents, trg_audit_tasks, trg_audit_executions, trg_audit_users)
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
--
-- Why it's a standalone function, not inlined in a trigger file: it's reused by 5
-- different triggers across 2 schemas — it belongs with the other reusable functions
-- in this folder, not owned by any single trigger.
--
-- Why it exists: this is a full audit trail (approach.md §4), independent from the
-- business triggers — its purpose is auditing, security, and error recovery, not
-- enforcing business rules, so it's never counted toward the business-trigger
-- minimum (approach.md §3).

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
