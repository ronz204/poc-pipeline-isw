-- Custom SQL migration file --
GRANT USAGE ON SCHEMA auth TO runner, backuper;

--> statement-breakpoint
GRANT SELECT, INSERT, UPDATE, DELETE 
ON ALL TABLES IN SCHEMA "auth" TO runner, backuper;

--> statement-breakpoint
ALTER DEFAULT PRIVILEGES FOR ROLE sampler IN SCHEMA "auth" 
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO runner, backuper;
