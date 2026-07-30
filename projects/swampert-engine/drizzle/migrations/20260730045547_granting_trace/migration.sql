-- Custom SQL migration file --
GRANT USAGE ON SCHEMA "trace" TO runner, backuper;

--> statement-breakpoint
GRANT SELECT
ON ALL TABLES IN SCHEMA "trace" TO runner, backuper;

--> statement-breakpoint
ALTER DEFAULT PRIVILEGES FOR ROLE sampler IN SCHEMA "trace"
GRANT SELECT ON TABLES TO runner, backuper;
