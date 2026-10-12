from collections import Counter
from datetime import date
from pathlib import Path

import pytest

from source.extract import extract
from source.generator import (
  CLEAN_FILE,
  DEFECTIVE_FILE,
  clean_rows,
  defective_rows,
  generate_datasets,
)
from source.validate import validate

DATA_DIR = Path(__file__).parents[1] / "data"
LIMIT = 50 * 1024 * 1024


@pytest.fixture(scope="module")
def generated(tmp_path_factory) -> tuple[Path, Path]:
  return generate_datasets(tmp_path_factory.mktemp("datasets"))


def test_same_seed_produces_the_same_bytes_every_time(tmp_path, generated):
  clean, defective = generate_datasets(tmp_path / "again")

  assert clean.read_bytes() == generated[0].read_bytes()
  assert defective.read_bytes() == generated[1].read_bytes()


def test_generator_reproduces_the_committed_datasets_byte_for_byte(generated):
  assert generated[0].read_bytes() == (DATA_DIR / CLEAN_FILE).read_bytes()
  assert generated[1].read_bytes() == (DATA_DIR / DEFECTIVE_FILE).read_bytes()


def test_output_files_are_named_and_created_in_the_given_directory(tmp_path):
  clean, defective = generate_datasets(tmp_path / "nested" / "out")

  assert (clean.name, defective.name) == (CLEAN_FILE, DEFECTIVE_FILE)
  assert clean.parent == defective.parent == tmp_path / "nested" / "out"


def test_each_dataset_has_one_thousand_rows(generated):
  assert len(clean_rows()) == len(defective_rows()) == 1000
  assert all(extract(path, LIMIT).rows_in == 1000 for path in generated)


def test_identifier_ranges_are_disjoint_so_both_files_load_together():
  clean_ids = {row[0] for row in clean_rows()}
  defective_ids = {row[0] for row in defective_rows()}

  assert clean_ids.isdisjoint(defective_ids)
  assert len(clean_ids) == 1000


def test_dates_fall_within_2025():
  for row in clean_rows() + defective_rows():
    day = row[5]
    if day not in {"2025-02-30", "2025-13-01"}:
      assert date(2025, 1, 1) <= date.fromisoformat(day) <= date(2025, 12, 31)


def test_about_eight_percent_of_clean_rows_have_messy_text():
  messy = sum(
    1
    for row in clean_rows()
    if any(v != " ".join(v.split()) or v.islower() or v.isupper() for v in (row[1], row[2], row[6]))
  )

  assert 50 <= messy <= 110


def test_clean_dataset_validates_with_no_rejections(generated):
  result = validate(extract(generated[0], LIMIT))

  assert result.rejected == ()
  assert len(result.valid) == 1000


def test_defective_dataset_yields_exactly_12_rejections_and_988_valid_rows(generated):
  result = validate(extract(generated[1], LIMIT))

  assert len(result.rejected) == 12
  assert len(result.valid) == 988
  assert Counter(code for rejection in result.rejected for code in rejection.reasons) == {
    "non_positive_unit_price": 3,
    "missing_product": 2,
    "duplicate_transaction_id": 2,
    "invalid_transaction_date": 2,
    "invalid_quantity": 2,
    "invalid_unit_price": 1,
  }


def test_each_defect_is_planted_at_its_fixed_position(generated):
  result = validate(extract(generated[1], LIMIT))

  by_record = {rejection.record_number: rejection.reasons for rejection in result.rejected}
  assert by_record == {
    122: ("non_positive_unit_price",),
    482: ("non_positive_unit_price",),
    762: ("non_positive_unit_price",),
    207: ("missing_product",),
    642: ("missing_product",),
    332: ("duplicate_transaction_id",),
    882: ("duplicate_transaction_id",),
    57: ("invalid_transaction_date",),
    912: ("invalid_transaction_date",),
    412: ("invalid_quantity",),
    692: ("invalid_quantity",),
    1001: ("invalid_unit_price",),
  }
