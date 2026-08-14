-- Function: core.fn_stale_swarms
-- Kind: table-returning — TABLE(swarm_id uuid, tenant_id uuid, last_task_at timestamptz)
-- Used by: core.sp_archive_stale_swarms
--
-- What it does: lists every active, non-deleted swarm that has gone quiet — no task
-- created after p_inactive_since, and no execution still pending or running. A swarm
-- that never had a task at all counts as stale and comes back with last_task_at NULL.
--
-- Why it exists: "which swarms are stale?" is a non-trivial read (an aggregate over
-- tasks plus a NOT EXISTS over executions) that the archiving procedure re-runs on
-- every loop iteration. Keeping it as a function means the definition of "stale"
-- lives in one place and can also be queried directly, e.g. to preview what a run of
-- sp_archive_stale_swarms would touch before actually calling it.
--
-- Under FORCE ROW LEVEL SECURITY this only ever returns swarms of the tenant in
-- app.current_tenant_id — it is not a cross-tenant sweep.
--
-- Example: SELECT * FROM core.fn_stale_swarms(now() - interval '90 days');

CREATE OR REPLACE FUNCTION core.fn_stale_swarms(p_inactive_since timestamptz)
RETURNS TABLE (
  swarm_id uuid,
  tenant_id uuid,
  last_task_at timestamptz
) AS $$
BEGIN
  RETURN QUERY
  SELECT s.id, s.tenant_id, max(t.created_at)
  FROM core.swarms s
  LEFT JOIN core.tasks t
    ON t.swarm_id = s.id
   AND t.deleted_at IS NULL
  WHERE s.status = 'active'
    AND s.deleted_at IS NULL
  GROUP BY s.id, s.tenant_id
  HAVING coalesce(max(t.created_at), '-infinity'::timestamptz) < p_inactive_since
     AND NOT EXISTS (
       SELECT 1
       FROM core.executions e
       JOIN core.tasks ot ON ot.id = e.task_id
       WHERE ot.swarm_id = s.id
         AND e.status IN ('pending', 'running')
         AND e.deleted_at IS NULL
     )
  ORDER BY max(t.created_at) NULLS FIRST;
END;
$$ LANGUAGE plpgsql STABLE;
