CREATE SCHEMA IF NOT EXISTS "extensions";
CREATE EXTENSION IF NOT EXISTS pgcrypto SCHEMA extensions;


SELECT 'CREATE ROLE sampler WITH LOGIN PASSWORD ' || quote_literal(:'sampler_password') || ' NOBYPASSRLS'
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sampler')
\gexec

SELECT 'CREATE ROLE runner WITH LOGIN PASSWORD ' || quote_literal(:'runner_password') || ' NOBYPASSRLS'
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'runner')
\gexec

SELECT 'CREATE ROLE backuper WITH LOGIN PASSWORD ' || quote_literal(:'backuper_password') || ' NOBYPASSRLS'
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'backuper')
\gexec


GRANT USAGE ON SCHEMA extensions TO sampler, runner, backuper;

GRANT CONNECT ON DATABASE :"db_name" TO sampler, runner, backuper;

GRANT CREATE ON DATABASE :"db_name" TO sampler;
