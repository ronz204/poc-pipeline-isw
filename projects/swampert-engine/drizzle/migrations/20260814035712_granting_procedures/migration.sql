-- Custom SQL migration file --
-- DCL for the 5 procedures installed in 20260814035209_modeling_procedures —
-- documented in full in deltas/process.spec.md § Implementation § Migration.
--
-- FORCE ROW LEVEL SECURITY: 4 of the 5 procedures are SECURITY DEFINER, so their
-- bodies run as sampler (the owner of every table). ENABLE ROW LEVEL SECURITY
-- (already set on these 9 tables) exempts the table owner from its own policies by
-- default — FORCE is the one flag that makes tenant_isolation apply even to the
-- owner, which is what keeps a SECURITY DEFINER procedure from reading or writing
-- across every tenant instead of just the one in app.current_tenant_id.
--
-- No REVOKE statement: runner keeps every direct table privilege it has today
-- (deltas/process.spec.md § Scope confirms this slice is additive only).

ALTER TABLE auth.users FORCE ROW LEVEL SECURITY;
--> statement-breakpoint
ALTER TABLE core.swarms FORCE ROW LEVEL SECURITY;
--> statement-breakpoint
ALTER TABLE core.agents FORCE ROW LEVEL SECURITY;
--> statement-breakpoint
ALTER TABLE core.tasks FORCE ROW LEVEL SECURITY;
--> statement-breakpoint
ALTER TABLE core.executions FORCE ROW LEVEL SECURITY;
--> statement-breakpoint
ALTER TABLE trace.execution_steps FORCE ROW LEVEL SECURITY;
--> statement-breakpoint
ALTER TABLE trace.token_costs FORCE ROW LEVEL SECURITY;
--> statement-breakpoint
ALTER TABLE trace.execution_errors FORCE ROW LEVEL SECURITY;
--> statement-breakpoint
ALTER TABLE trace.audit_log FORCE ROW LEVEL SECURITY;

-- EXECUTE grants: Postgres grants EXECUTE on new routines to PUBLIC by default, so
-- runner could already CALL these 5 procedures without this. This documents intent
-- explicitly rather than relying on the PUBLIC default — revoking EXECUTE from
-- PUBLIC first is what would make it load-bearing instead of documentation, and
-- that revocation is deliberately not part of this migration (see database.md's
-- "current phase" note on runner's privileges).
--> statement-breakpoint
GRANT EXECUTE ON PROCEDURE core.sp_launch_execution(uuid, integer)
  TO runner;
--> statement-breakpoint
GRANT EXECUTE ON PROCEDURE core.sp_complete_execution(uuid, core.execution_status, integer)
  TO runner;
--> statement-breakpoint
GRANT EXECUTE ON PROCEDURE trace.sp_record_execution_step(uuid, uuid, jsonb, text[], integer, integer, numeric, numeric)
  TO runner;
--> statement-breakpoint
GRANT EXECUTE ON PROCEDURE core.sp_provision_swarm_roster(uuid, uuid[])
  TO runner;
--> statement-breakpoint
GRANT EXECUTE ON PROCEDURE core.sp_archive_stale_swarms(timestamptz)
  TO runner;
