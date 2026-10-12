import csv

import pytest

from source.ingest.reader import REQUIRED_COLUMNS
from source.ingest.rules import Rejection
from source.output.exports import neutralize, write_rejected_csv

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
