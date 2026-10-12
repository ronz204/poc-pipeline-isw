from collections.abc import Generator
from contextlib import contextmanager
from datetime import UTC, datetime
from time import perf_counter

import psycopg

from source.engine.status import FAILED, RUNNING, RunResult, failure_message
from source.storage.runs import finish_run, insert_run


@contextmanager
def audited_run(
  conn: psycopg.Connection, run_id: str, source_file: str, result: RunResult | None = None
) -> Generator[RunResult, None, None]:
  started_at = datetime.now(UTC)
  clock = perf_counter()
  insert_run(conn, run_id, source_file, started_at)
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
    finish_run(conn, run_id, result, datetime.now(UTC), round((perf_counter() - clock) * 1000))
