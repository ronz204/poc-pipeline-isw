from pathlib import Path

import psycopg

from source.config.settings import Settings

CONNECT_TIMEOUT_SECONDS = 5
SCHEMA_FILE = Path(__file__).with_name("schema.sql")


def connect(settings: Settings) -> psycopg.Connection:
  return psycopg.connect(
    **settings.connection_params(), autocommit=True, connect_timeout=CONNECT_TIMEOUT_SECONDS
  )


def ensure_schema(conn: psycopg.Connection) -> None:
  conn.execute(SCHEMA_FILE.read_text(encoding="utf-8"))
