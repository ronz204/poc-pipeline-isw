from collections.abc import Generator
from contextlib import contextmanager
from dataclasses import dataclass, field
from datetime import UTC, datetime
from time import perf_counter

import psycopg
from psycopg.types.json import Jsonb

RUNNING = "RUNNING"
SUCCESS = "SUCCESS"
SUCCESS_WITH_REJECTS = "SUCCESS_WITH_REJECTS"
FAILED = "FAILED"


class RunError(Exception):
  pass


def failure_message(exc: BaseException) -> str:
  return str(exc) if isinstance(exc, RunError) else type(exc).__name__


@dataclass
class RunResult:
  status: str = RUNNING
  rows_in: int | None = None
  rows_valid: int | None = None
  rows_rejected: int | None = None
  rows_loaded: int | None = None
  rows_skipped_existing: int | None = None
  rejection_breakdown: dict[str, int] = field(default_factory=dict)
  reconciled: bool = False
  error: str | None = None


@contextmanager
def audited_run(
  conn: psycopg.Connection, run_id: str, source_file: str, result: RunResult | None = None
) -> Generator[RunResult, None, None]:
  started_at = datetime.now(UTC)
  clock = perf_counter()
  conn.execute(
    "INSERT INTO etl_runs (run_id, source_file, status, started_at) VALUES (%s, %s, %s, %s)",
    (run_id, source_file, RUNNING, started_at),
  )
  result = result or RunResult()
  try:
    yield result
  except BaseException as exc:
    result.status = FAILED
    result.error = failure_message(exc)
    raise
  finally:
    if result.status == RUNNING:
      result.status = FAILED
      result.error = "run ended without a final status"
    _finish(
      conn, run_id, result, finished_at=datetime.now(UTC), duration_ms=round((perf_counter() - clock) * 1000)
    )


def _finish(
  conn: psycopg.Connection, run_id: str, result: RunResult, finished_at: datetime, duration_ms: int
) -> None:
  conn.execute(
    """
    UPDATE etl_runs
    SET status = %s, finished_at = %s, duration_ms = %s,
        rows_in = %s, rows_valid = %s, rows_rejected = %s,
        rows_loaded = %s, rows_skipped_existing = %s,
        rejection_breakdown = %s, error_message = %s
    WHERE run_id = %s
    """,
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
