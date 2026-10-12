import csv

import psycopg
import pytest

from source.config.settings import load_settings
from source.ingest.reader import REQUIRED_COLUMNS
from source.ingest.rules import Rejection
from source.storage.rejects import neutralize, persist_rejections, write_rejected_csv

FIELDS = ("7", "Widget", "tools", "0", "2.50", "2025-01-01", "peru")
REJECTED = Rejection(3, ("invalid_quantity",), FIELDS)
SHORT = Rejection(4, ("wrong_column_count",), ("8", "Gadget"))


def read_csv(path):
  with path.open(encoding="utf-8", newline="") as handle:
    return list(csv.reader(handle))


@pytest.mark.parametrize("prefix", ["=", "+", "-", "@", "\t", "\r"])
def test_formula_prefixes_are_neutralized(prefix):
  assert neutralize(f"{prefix}cmd") == f"'{prefix}cmd"


@pytest.mark.parametrize("cell", ["", "plain", "a=b", "'quoted", " =padded"])
def test_other_cells_are_untouched(cell):
  assert neutralize(cell) == cell


def test_no_rejections_writes_no_file(tmp_path):
  assert write_rejected_csv(tmp_path, "run-a", []) is None
  assert list(tmp_path.iterdir()) == []


def test_csv_lists_each_rejection_with_reasons_and_original_values(tmp_path):
  both = Rejection(5, ("missing_product", "invalid_quantity"), ("9", "", "c", "", "1.00", "2025-01-02", "x"))

  path = write_rejected_csv(tmp_path / "out", "run-a", [REJECTED, both])

  assert path == tmp_path / "out" / "run-a_rejected.csv"
  header, first, second = read_csv(path)
  assert header[:2] == ["record_number", "reasons"]
  assert header[2:9] == list(REQUIRED_COLUMNS)
  assert first == ["3", "invalid_quantity", *FIELDS, ""]
  assert second[:2] == ["5", "missing_product;invalid_quantity"]


def test_csv_keeps_wrong_column_count_values_unmapped(tmp_path):
  _, row = read_csv(write_rejected_csv(tmp_path, "run-a", [SHORT]))

  assert row == ["4", "wrong_column_count", *[""] * len(REQUIRED_COLUMNS), "8|Gadget"]


def test_csv_neutralizes_formula_cells(tmp_path):
  hostile = Rejection(2, ("invalid_unit_price",), ("1", "=HYPERLINK(1)", "@c", "1", "-5.00", "d", "+c"))

  _, row = read_csv(write_rejected_csv(tmp_path, "run-a", [hostile]))

  assert row[3] == "'=HYPERLINK(1)"
  assert row[4] == "'@c"
  assert row[6] == "'-5.00"
  assert row[8] == "'+c"


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
