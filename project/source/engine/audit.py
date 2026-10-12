from collections.abc import Generator
from contextlib import contextmanager
from datetime import UTC, datetime
from time import perf_counter

import psycopg

from source.engine.status import FAILED, RUNNING, RunResult, failure_message
from source.storage.runs import finish_run, insert_run


@contextmanager
def audited_run(conn: psycopg.Connection, result: RunResult) -> Generator[None, None, None]:
  clock = perf_counter()
  insert_run(conn, result, datetime.now(UTC))
  try:
    yield
  except BaseException as exc:
    result.status = FAILED
    result.error = failure_message(exc)
    raise
  finally:
    if result.status == RUNNING:
      result.status = FAILED
      result.error = "run ended without a final status"
    result.duration_ms = round((perf_counter() - clock) * 1000)
    finish_run(conn, result, datetime.now(UTC))
