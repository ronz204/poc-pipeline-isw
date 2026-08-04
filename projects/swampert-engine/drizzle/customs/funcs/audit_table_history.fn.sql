-- Function: trace.fn_table_history
-- Role: query function (not a trigger) — reads what the audit triggers in
-- drizzle/customs/triggers/audit_log_changes.trg.sql wrote.
--
-- What it does: returns every trace.audit_log row recorded for a given table name,
-- most recent first.
--
-- Why it exists: this is the query counterpart approach.md §4 asks for (referred to
-- there as "ver_historial_tabla(nombre_tabla)") — one place to look up a table's
-- full change history instead of every caller writing its own audit_log query.
-- Named in English here, unlike the Spanish name in approach.md's own wording, to
-- stay consistent with the rest of the schema.

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
