from datetime import datetime

import psycopg
from psycopg.types.json import Jsonb

from source.engine.status import RUNNING, RunResult

INSERT_RUN = "INSERT INTO etl_runs (run_id, source_file, status, started_at) VALUES (%s, %s, %s, %s)"
UPDATE_RUN = """
  UPDATE etl_runs
  SET status = %s, finished_at = %s, duration_ms = %s,
      rows_in = %s, rows_valid = %s, rows_rejected = %s,
      rows_loaded = %s, rows_skipped_existing = %s,
      rejection_breakdown = %s, error_message = %s
  WHERE run_id = %s
"""


def insert_run(conn: psycopg.Connection, run_id: str, source_file: str, started_at: datetime) -> None:
  conn.execute(INSERT_RUN, (run_id, source_file, RUNNING, started_at))


def finish_run(
  conn: psycopg.Connection, run_id: str, result: RunResult, finished_at: datetime, duration_ms: int
) -> None:
  conn.execute(
    UPDATE_RUN,
    (
      result.status,
      finished_at,
      duration_ms,
      result.rows_in,
      result.rows_valid,
      result.rows_rejected,
      result.rows_loaded,
      result.rows_skipped_existing,
      Jsonb(result.rejection_breakdown),
      result.error,
      run_id,
    ),
  )
