-- Custom SQL migration file --
GRANT USAGE ON SCHEMA "auth" TO runner, backuper;

--> statement-breakpoint
GRANT SELECT
ON ALL TABLES IN SCHEMA "auth" TO runner, backuper;

--> statement-breakpoint
GRANT INSERT, UPDATE, DELETE
ON ALL TABLES IN SCHEMA "auth" TO runner;

--> statement-breakpoint
ALTER DEFAULT PRIVILEGES FOR ROLE sampler IN SCHEMA "auth"
GRANT SELECT ON TABLES TO runner, backuper;

--> statement-breakpoint
ALTER DEFAULT PRIVILEGES FOR ROLE sampler IN SCHEMA "auth"
GRANT INSERT, UPDATE, DELETE ON TABLES TO runner;
