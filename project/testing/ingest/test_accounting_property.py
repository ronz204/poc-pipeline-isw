import csv
import tempfile
from pathlib import Path

from hypothesis import HealthCheck, given, settings
from hypothesis import strategies as st

from source.config.settings import BYTES_PER_MB, DEFAULT_MAX_INPUT_MB
from source.ingest.reader import REQUIRED_COLUMNS, extract
from source.ingest.rules import REASON_CODES, validate
from source.ingest.shaper import transform

LIMIT = int(DEFAULT_MAX_INPUT_MB * BYTES_PER_MB)
TEXT = st.text(alphabet=st.characters(blacklist_categories=("Cs",)), max_size=12)
PLAUSIBLE = st.sampled_from(
  [
    "",
    " ",
    "1",
    "7",
    "0007",
    "9999",
    "10000",
    "0",
    "-5.00",
    "0.00",
    "10.50",
    "1.234",
    "2025-02-21",
    "2025-02-30",
  ]
)
CELL = st.one_of(TEXT, PLAUSIBLE)
ROW = st.one_of(
  st.lists(CELL, min_size=7, max_size=7),
  st.lists(CELL, min_size=7, max_size=7).map(lambda cells: [str(len(cells)), *cells[1:]]),
  st.lists(CELL, max_size=10),
)


def run(rows: list[list[str]]):
  with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / "input.csv"
    with path.open("w", newline="", encoding="utf-8") as handle:
      writer = csv.writer(handle, lineterminator="\n")
      writer.writerow(REQUIRED_COLUMNS)
      writer.writerows(rows)
    extracted = extract(path, LIMIT)
  return extracted, validate(extracted)


@settings(max_examples=120, deadline=None, suppress_health_check=[HealthCheck.too_slow])
@given(st.lists(ROW, max_size=30))
def test_valid_plus_rejected_equals_input_for_any_input(rows):
  extracted, result = run(rows)

  assert extracted.rows_in == len(rows)
  assert len(result.valid) + len(result.rejected) == len(rows)

  valid_numbers = set(result.valid.index)
  rejected_numbers = {rejection.record_number for rejection in result.rejected}
  assert valid_numbers.isdisjoint(rejected_numbers)
  assert valid_numbers | rejected_numbers == set(range(2, len(rows) + 2))

  for rejection in result.rejected:
    assert rejection.reasons
    assert set(rejection.reasons) <= set(REASON_CODES)


@settings(max_examples=120, deadline=None, suppress_health_check=[HealthCheck.too_slow])
@given(st.lists(ROW, max_size=30))
def test_valid_identifiers_are_unique_and_every_valid_row_transforms(rows):
  _, result = run(rows)

  sales = transform(result.valid)

  assert len(sales) == len(result.valid)
  assert len({sale.transaction_id for sale in sales}) == len(sales)
  assert all(sale.total == sale.quantity * sale.unit_price for sale in sales)
  assert all(1 <= sale.quantity <= 9999 and sale.unit_price > 0 for sale in sales)
