import psycopg
import pytest

from source.config.settings import load_settings
from source.ingest.reader import REQUIRED_COLUMNS
from source.ingest.rules import Rejection
from source.storage.rejects import persist_rejections

FIELDS = ("7", "Widget", "tools", "0", "2.50", "2025-01-01", "peru")
REJECTED = Rejection(3, ("invalid_quantity",), FIELDS)
SHORT = Rejection(4, ("wrong_column_count",), ("8", "Gadget"))


def select_rejected(conn, run_id):
  return conn.execute(
    "SELECT record_number, reasons, raw FROM rejected_records WHERE run_id = %s ORDER BY record_number",
    (run_id,),
  ).fetchall()


@pytest.mark.integration
def test_rejections_are_persisted_with_reasons_and_original_values(conn, make_run):
  run_id = make_run("quarantine")

  persist_rejections(conn, run_id, [REJECTED, SHORT])

  assert select_rejected(conn, run_id) == [
    (3, ["invalid_quantity"], dict(zip(REQUIRED_COLUMNS, FIELDS, strict=True))),
    (4, ["wrong_column_count"], ["8", "Gadget"]),
  ]


@pytest.mark.integration
def test_persisting_nothing_is_a_no_op(conn, make_run):
  run_id = make_run("quarantine-empty")

  persist_rejections(conn, run_id, [])

  assert select_rejected(conn, run_id) == []


@pytest.mark.integration
def test_rejections_are_committed_immediately(conn, make_run):
  run_id = make_run("quarantine-commit")
  persist_rejections(conn, run_id, [REJECTED])

  with psycopg.connect(**load_settings().connection_params()) as other:
    count = other.execute("SELECT count(*) FROM rejected_records WHERE run_id = %s", (run_id,)).fetchone()
  assert count == (1,)


@pytest.mark.integration
def test_rejection_without_reasons_is_refused_by_the_database(conn, make_run):
  run_id = make_run("quarantine-check")

  with pytest.raises(psycopg.errors.CheckViolation):
    persist_rejections(conn, run_id, [Rejection(2, (), FIELDS)])
  assert select_rejected(conn, run_id) == []
