-- Custom SQL migration file, put your code below! --

-- Las funciones de trigger (fn_log_audit_change) no necesitan GRANT EXECUTE: Postgres
-- las invoca automáticamente con el DML, sin que el rol que dispara el evento necesite
-- privilegio de ejecución directo. fn_ver_historial_tabla sí se llama directamente.
GRANT EXECUTE ON FUNCTION trace.fn_ver_historial_tabla(text) TO runner;
