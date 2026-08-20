#!/bin/sh
set -eu

psql -v ON_ERROR_STOP=1 \
  --username "$POSTGRES_USER" \
  --dbname "$POSTGRES_DB" \
  -v db_name="$POSTGRES_DB" \
  -v sampler_password="$POSTGRES_SAMPLER_PASSWORD" \
  -v runner_password="$POSTGRES_RUNNER_PASSWORD" \
  -v backuper_password="$POSTGRES_BACKUPER_PASSWORD" \
  -f /docker-entrypoint-initdb.d/database/bootstrap.sql
