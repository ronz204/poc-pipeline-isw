-- Procedure: core.sp_archive_stale_swarms
-- Tables written: core.swarms, core.tasks | Control flow: WHILE
-- Transaction: explicit — one COMMIT per swarm, inside the loop. This is the only
-- procedure in this slice that commits mid-run, and the reason it is a PROCEDURE and
-- not a FUNCTION: a function cannot control transactions in Postgres.
--
-- It is also the only one that is NOT SECURITY DEFINER, and that is forced, not a
-- preference: Postgres raises "invalid transaction termination" on a COMMIT inside a
-- SECURITY DEFINER routine (verified against Postgres 16), so a procedure cannot both
-- run as the owner and commit per iteration. Committing per swarm is this procedure's
-- whole point, so it runs as the caller instead — which today is runner, and runner
-- already holds direct UPDATE on core.swarms/core.tasks (database.md § Postgres
-- roles). If runner's direct table privileges are ever revoked, this procedure needs
-- its own GRANT on those two tables — the other four keep working untouched.
--
-- What it does: batch job. Takes every swarm core.fn_stale_swarms reports as quiet,
-- archives it, and fails the tasks it left open ('pending'/'progress'), one swarm at
-- a time, committing each before moving on.
--
-- Why it exists: cleaning up abandoned swarms by hand means running the staleness
-- query, then two updates per result, and getting the order right so a swarm isn't
-- archived while it still has work running. As a batch job it also has to survive
-- being interrupted, which is what the per-swarm COMMIT buys: swarms already
-- processed stay archived, the rest are simply untouched.
--
-- Parameters:
--   p_inactive_since  — cutoff timestamp. A swarm counts as stale when it has no task
--                       created after this moment and no pending/running execution.
--                       Must not be in the future — that would archive everything.
--
-- The loop re-runs fn_stale_swarms each iteration instead of holding a cursor open:
-- a cursor is closed by the COMMIT, and re-querying is safe precisely because an
-- archived swarm no longer matches (fn_stale_swarms only looks at active ones). The
-- ROW_COUNT guard below is what keeps that from becoming an infinite loop if an
-- UPDATE ever matches nothing (missing tenant context under FORCE RLS is the
-- realistic way that happens).
--
-- Scope note: under RLS this archives only the swarms of the tenant in
-- app.current_tenant_id, so it is a per-tenant job, not a global sweep.
--
-- Calling contract: must be called outside a client-opened transaction, with the
-- tenant set at session level — the COMMITs below would otherwise discard a
-- transaction-local setting halfway through the run (see core.sp_launch_execution's
-- header). The value is re-applied after each COMMIT for exactly that reason.
--
-- Example:
--   SELECT set_config('app.current_tenant_id', '018f0000-0000-7000-8000-0000000000ff', false);
--   CALL core.sp_archive_stale_swarms(now() - interval '90 days');

CREATE OR REPLACE PROCEDURE core.sp_archive_stale_swarms(p_inactive_since timestamptz)
LANGUAGE plpgsql
AS $$
DECLARE
  v_swarm_id uuid;
  v_last_task_at timestamptz;
  v_has_stale boolean;
  v_archived_swarms integer := 0;
  v_failed_tasks integer := 0;
  v_row_count integer;
  v_tenant_ctx text;
BEGIN
  IF p_inactive_since IS NULL THEN
    RAISE EXCEPTION 'p_inactive_since is required'
      USING ERRCODE = 'null_value_not_allowed';
  END IF;

  IF p_inactive_since > now() THEN
    RAISE EXCEPTION 'p_inactive_since (%) is in the future: that would archive every active swarm',
      p_inactive_since
      USING ERRCODE = 'check_violation';
  END IF;

  v_tenant_ctx := NULLIF(current_setting('app.current_tenant_id', true), '');

  SELECT s.swarm_id, s.last_task_at
    INTO v_swarm_id, v_last_task_at
  FROM core.fn_stale_swarms(p_inactive_since) s
  LIMIT 1;

  v_has_stale := FOUND;

  WHILE v_has_stale
  LOOP
    UPDATE core.swarms
    SET status = 'archived'
    WHERE id = v_swarm_id;

    GET DIAGNOSTICS v_row_count = ROW_COUNT;

    IF v_row_count = 0 THEN
      RAISE EXCEPTION 'Swarm % is stale but could not be archived — is app.current_tenant_id set?',
        v_swarm_id
        USING ERRCODE = 'check_violation';
    END IF;

    UPDATE core.tasks
    SET status = 'failed'
    WHERE swarm_id = v_swarm_id
      AND status IN ('pending', 'progress')
      AND deleted_at IS NULL;

    GET DIAGNOSTICS v_row_count = ROW_COUNT;
    v_failed_tasks := v_failed_tasks + v_row_count;
    v_archived_swarms := v_archived_swarms + 1;

    RAISE NOTICE 'Archived swarm % (last task at %), % open task(s) failed',
      v_swarm_id, v_last_task_at, v_row_count;

    -- Each swarm is independent: committing here is what makes an interrupted run
    -- leave finished swarms archived instead of undoing the whole batch.
    COMMIT;

    IF v_tenant_ctx IS NOT NULL THEN
      PERFORM set_config('app.current_tenant_id', v_tenant_ctx, false);
    END IF;

    SELECT s.swarm_id, s.last_task_at
      INTO v_swarm_id, v_last_task_at
    FROM core.fn_stale_swarms(p_inactive_since) s
    LIMIT 1;

    v_has_stale := FOUND;
  END LOOP;

  RAISE NOTICE 'Done: % swarm(s) archived, % task(s) failed', v_archived_swarms, v_failed_tasks;
END;
$$;
