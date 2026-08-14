-- Procedure: reports.sp_refresh_reports
-- Tables written: reports.monthly_execution_summary, reports.swarm_task_summary,
-- reports.error_summary | Control flow: FOR
-- Transaction: the whole refresh — every tenant, all 3 tables, for the target
-- month — is one inner BEGIN/EXCEPTION subtransaction, the same pattern the 4
-- SECURITY DEFINER procedures in deltas/process.spec.md already use. No COMMIT
-- statement: Postgres rejects transaction control inside SECURITY DEFINER
-- routines, so unlike core.sp_archive_stale_swarms (which commits per swarm on
-- purpose), this procedure cannot commit per tenant — the CALL itself is the
-- only commit boundary.
--
-- Why SECURITY DEFINER: a single app.current_tenant_id session value can only
-- ever represent one tenant under RLS. Recalculating every tenant's reports in
-- one CALL therefore has no choice but to run as sampler (the table owner) and
-- manage tenant context explicitly, one tenant at a time — exactly the
-- "explicit, audited SECURITY DEFINER function" database.md names as the
-- correct way to cross tenant boundaries, instead of ever granting BYPASSRLS.
--
-- The critical detail: FORCE ROW LEVEL SECURITY already applies to
-- core.executions/core.tasks/trace.execution_errors/trace.token_costs (see
-- 20260814035712_granting_procedures) as much as it does to reports.* here — so
-- reading from those tables as sampler is just as tenant-scoped as writing to
-- reports.* is. A single set-based INSERT ... SELECT ... GROUP BY tenant_id
-- across all tenants would silently see only one tenant (or none), not fail
-- loudly. Each loop iteration calls set_config('app.current_tenant_id', ...)
-- (the SET LOCAL equivalent inside plpgsql) before its reads and writes, so
-- every statement below is automatically scoped to that one tenant by the
-- existing tenant_isolation policies — no explicit WHERE tenant_id = ... is
-- written anywhere in this body, RLS does it.
--
-- What it does: recalculates one calendar month's worth of report data —
-- monthly_execution_summary and error_summary for that month, and a fresh
-- swarm_task_summary snapshot (which has no time dimension) — across every
-- active tenant, replacing whatever was there (DELETE + re-INSERT), never
-- accumulating or duplicating across repeated runs of the same period.
--
-- Parameters:
--   p_period  — any date within the target month; truncated internally to the
--               1st of that month. Required.
--
-- Example:
--   CALL reports.sp_refresh_reports('2026-08-01');

CREATE OR REPLACE PROCEDURE reports.sp_refresh_reports(p_period date)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_period date;
  v_tenant record;
BEGIN
  IF p_period IS NULL THEN
    RAISE EXCEPTION 'p_period is required'
      USING ERRCODE = 'null_value_not_allowed';
  END IF;

  v_period := date_trunc('month', p_period)::date;

  BEGIN
    FOR v_tenant IN SELECT id FROM auth.tenants WHERE deleted_at IS NULL
    LOOP
      PERFORM set_config('app.current_tenant_id', v_tenant.id::text, true);

      DELETE FROM reports.monthly_execution_summary WHERE period = v_period;

      INSERT INTO reports.monthly_execution_summary
        (tenant_id, period, execution_count, avg_duration_seconds, total_cost, refreshed_at)
      SELECT
        v_tenant.id, v_period, count(*),
        avg(EXTRACT(EPOCH FROM (e.finished_at - e.started_at))) FILTER (WHERE e.finished_at IS NOT NULL),
        coalesce(sum(tc.estimated_cost), 0), now()
      FROM core.executions e
      LEFT JOIN trace.token_costs tc ON tc.execution_id = e.id AND tc.deleted_at IS NULL
      WHERE e.deleted_at IS NULL
        AND e.started_at >= v_period
        AND e.started_at < v_period + interval '1 month'
      HAVING count(*) > 0;

      DELETE FROM reports.swarm_task_summary;

      INSERT INTO reports.swarm_task_summary (tenant_id, swarm_id, task_status, task_count, refreshed_at)
      SELECT v_tenant.id, t.swarm_id, t.status, count(*), now()
      FROM core.tasks t
      WHERE t.deleted_at IS NULL
      GROUP BY t.swarm_id, t.status;

      DELETE FROM reports.error_summary WHERE period = v_period;

      INSERT INTO reports.error_summary (tenant_id, period, severity, error_count, refreshed_at)
      SELECT v_tenant.id, v_period, ee.severity, count(*), now()
      FROM trace.execution_errors ee
      WHERE ee.deleted_at IS NULL
        AND ee.occurred_at >= v_period
        AND ee.occurred_at < v_period + interval '1 month'
      GROUP BY ee.severity;
    END LOOP;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'sp_refresh_reports rolled back for period %: %', v_period, SQLERRM
      USING ERRCODE = SQLSTATE;
  END;

  RAISE NOTICE 'Refreshed reports for period %', v_period;
END;
$$;
