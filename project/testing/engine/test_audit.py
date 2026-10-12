import uuid

import psycopg
import pytest

from source.config.settings import load_settings
from source.engine.audit import audited_run
from source.engine.status import FAILED, RUNNING, SUCCESS_WITH_REJECTS, RunError, RunResult

SELECT_RUN = """
  SELECT status, finished_at, duration_ms, rows_in, rows_valid, rows_rejected,
         rows_loaded, rows_skipped_existing, rejection_breakdown, error_message
  FROM etl_runs WHERE run_id = %s
"""


@pytest.fixture
def result(conn):
  run = RunResult(run_id=f"test-audit-{uuid.uuid4().hex[:8]}", source_file="data/sales_valid.csv")
  yield run
  conn.execute("DELETE FROM etl_runs WHERE run_id = %s", (run.run_id,))


def fetch(conn, run_id):
  return conn.execute(SELECT_RUN, (run_id,)).fetchone()


@pytest.mark.integration
def test_run_row_is_committed_as_running_before_the_body_finishes(conn, result):
  with audited_run(conn, result):
    with psycopg.connect(**load_settings().connection_params()) as other:
      assert other.execute("SELECT status FROM etl_runs WHERE run_id = %s", (result.run_id,)).fetchone() == (
        RUNNING,
      )


@pytest.mark.integration
def test_final_update_records_status_counts_and_breakdown(conn, result):
  with audited_run(conn, result):
    result.status = SUCCESS_WITH_REJECTS
    result.rows_in, result.rows_valid, result.rows_rejected = 1000, 988, 12
    result.rows_loaded, result.rows_skipped_existing = 988, 0
    result.rejection_breakdown = {"missing_product": 2, "duplicate_transaction_id": 2}

  status, finished_at, duration_ms, *counts, breakdown, error = fetch(conn, result.run_id)
  assert status == SUCCESS_WITH_REJECTS
  assert finished_at is not None and finished_at.utcoffset().total_seconds() == 0
  assert duration_ms >= 0
  assert counts == [1000, 988, 12, 988, 0]
  assert breakdown == {"missing_product": 2, "duplicate_transaction_id": 2}
  assert error is None


@pytest.mark.integration
def test_run_error_is_recorded_as_failed_with_null_counts_and_reraised(conn, result):
  with pytest.raises(RunError):
    with audited_run(conn, result):
      raise RunError("input file not found")

  status, finished_at, _, *counts, breakdown, error = fetch(conn, result.run_id)
  assert status == FAILED
  assert finished_at is not None
  assert counts == [None] * 5
  assert breakdown == {}
  assert error == "input file not found"


@pytest.mark.integration
def test_unexpected_exception_is_recorded_by_type_only(conn, result):
  with pytest.raises(ValueError):
    with audited_run(conn, result):
      raise ValueError("secret row value 4242")

  status, *_, error = fetch(conn, result.run_id)
  assert status == FAILED
  assert error == "ValueError"


@pytest.mark.integration
def test_body_that_never_sets_a_final_status_is_failed_not_left_running(conn, result):
  with audited_run(conn, result):
    pass

  status, *_, error = fetch(conn, result.run_id)
  assert status == FAILED
  assert error == "run ended without a final status"
