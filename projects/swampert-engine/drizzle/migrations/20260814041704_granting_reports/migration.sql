-- Custom SQL migration file --
-- DCL for the reports schema (deltas/reports.spec.md, approach.md §5).
--
-- runner gets SELECT + EXECUTE only, never direct INSERT/UPDATE/DELETE on
-- reports.* — unlike the "current phase" concession the 9 domain tables have
-- (database.md § Postgres roles), the reports schema is created after the
-- procedural layer already exists, so every write goes through
-- reports.sp_refresh_reports (20260814041643_modeling_reports_procedure) from
-- the very first migration.
--
-- FORCE ROW LEVEL SECURITY is applied from creation, not deferred the way it
-- was for the domain tables — sp_refresh_reports is SECURITY DEFINER from the
-- day it's written, so there is no window where sampler could bypass
-- tenant_isolation on these 3 tables.

GRANT USAGE ON SCHEMA reports TO runner, backuper;

--> statement-breakpoint
GRANT SELECT
ON ALL TABLES IN SCHEMA reports TO runner, backuper;

--> statement-breakpoint
ALTER DEFAULT PRIVILEGES FOR ROLE sampler IN SCHEMA reports
GRANT SELECT ON TABLES TO runner, backuper;

--> statement-breakpoint
ALTER TABLE reports.monthly_execution_summary FORCE ROW LEVEL SECURITY;
--> statement-breakpoint
ALTER TABLE reports.swarm_task_summary FORCE ROW LEVEL SECURITY;
--> statement-breakpoint
ALTER TABLE reports.error_summary FORCE ROW LEVEL SECURITY;

--> statement-breakpoint
GRANT EXECUTE ON PROCEDURE reports.sp_refresh_reports(date) TO runner;
