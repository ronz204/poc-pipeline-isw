-- Custom SQL migration file --
GRANT USAGE ON SCHEMA "core" TO runner, backuper;

--> statement-breakpoint
GRANT SELECT
ON ALL TABLES IN SCHEMA "core" TO runner, backuper;

--> statement-breakpoint
ALTER DEFAULT PRIVILEGES FOR ROLE sampler IN SCHEMA "core"
GRANT SELECT ON TABLES TO runner, backuper;
