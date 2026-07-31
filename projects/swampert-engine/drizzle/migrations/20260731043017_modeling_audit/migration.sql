-- Custom SQL migration file, put your code below! --

-- Fuente canónica: drizzle/customs/triggers/audit.trg.sql

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

  -- Un usuario recién creado todavía no tiene app.current_user_id seteado (se setea
  -- después de crear los usuarios, ver TenantScope.setActor) — se audita a sí mismo.
  IF v_actor IS NULL AND TG_TABLE_NAME = 'users' AND TG_OP = 'INSERT' THEN
    v_actor := NEW.id;
  END IF;

  IF TG_OP = 'DELETE' THEN
    v_entity_id := OLD.id;
    v_tenant_id := OLD.tenant_id;
    v_action := 'deleted';
    v_summary := format('%s eliminado (id=%s)', TG_TABLE_NAME, OLD.id);
  ELSIF TG_OP = 'UPDATE' THEN
    v_entity_id := NEW.id;
    v_tenant_id := NEW.tenant_id;
    v_action := 'updated';
    v_summary := format('%s actualizado (id=%s)', TG_TABLE_NAME, NEW.id);
  ELSE
    v_entity_id := NEW.id;
    v_tenant_id := NEW.tenant_id;
    v_action := 'created';
    v_summary := format('%s creado (id=%s)', TG_TABLE_NAME, NEW.id);
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
      -- password (auth.users) nunca queda en el rastro de auditoría, ni siquiera hasheado.
      'before', to_jsonb(OLD) - 'password',
      'after', to_jsonb(NEW) - 'password'
    ),
    now()
  );

  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_audit_swarms
  AFTER INSERT OR UPDATE OR DELETE ON core.swarms
  FOR EACH ROW EXECUTE FUNCTION trace.fn_log_audit_change();

CREATE TRIGGER trg_audit_agents
  AFTER INSERT OR UPDATE OR DELETE ON core.agents
  FOR EACH ROW EXECUTE FUNCTION trace.fn_log_audit_change();

CREATE TRIGGER trg_audit_tasks
  AFTER INSERT OR UPDATE OR DELETE ON core.tasks
  FOR EACH ROW EXECUTE FUNCTION trace.fn_log_audit_change();

CREATE TRIGGER trg_audit_executions
  AFTER INSERT OR UPDATE OR DELETE ON core.executions
  FOR EACH ROW EXECUTE FUNCTION trace.fn_log_audit_change();

CREATE TRIGGER trg_audit_users
  AFTER INSERT OR UPDATE OR DELETE ON auth.users
  FOR EACH ROW EXECUTE FUNCTION trace.fn_log_audit_change();

-- Función de consulta (approach.md §4): equivalente a ver_historial_tabla(nombre_tabla).
CREATE OR REPLACE FUNCTION trace.fn_ver_historial_tabla(p_table_name text)
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
