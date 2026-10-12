from collections import Counter
from pathlib import Path

import pandas as pd
import pytest

from source.ingest.reader import REQUIRED_COLUMNS, Extracted, MalformedRow, extract
from source.ingest.rules import REASON_CODES, validate

DATA_DIR = Path(__file__).parents[2] / "data"
GOOD = {
  "transaction_id": "1",
  "product": "Toy Car",
  "category": "Toys",
  "quantity": "7",
  "unit_price": "10.09",
  "transaction_date": "2025-02-21",
  "country": "Colombia",
}


def extracted(*rows: dict[str, str], malformed=()) -> Extracted:
  frame = pd.DataFrame(
    [[row[name] for name in REQUIRED_COLUMNS] for row in rows],
    columns=list(REQUIRED_COLUMNS),
    index=range(2, 2 + len(rows)),
    dtype=str,
  )
  return Extracted(rows=frame, malformed=tuple(malformed), extra_columns=())


def numbered(*rows: dict[str, str]) -> list[dict[str, str]]:
  return [row | {"transaction_id": str(position)} for position, row in enumerate(rows, start=1)]


def ids_extracted(*ids: str) -> Extracted:
  return extracted(*(GOOD | {"transaction_id": value} for value in ids))


def reasons_of(**overrides: str) -> tuple[str, ...]:
  result = validate(extracted(GOOD | overrides))
  return result.rejected[0].reasons if result.rejected else ()


def test_a_row_without_failures_is_valid():
  result = validate(extracted(GOOD))

  assert result.rejected == ()
  assert len(result.valid) == 1


@pytest.mark.parametrize("blank", ["", "   ", "\t", " \t "])
@pytest.mark.parametrize(
  ("field", "expected"),
  [
    ("transaction_id", ("missing_transaction_id", "invalid_transaction_id")),
    ("product", ("missing_product",)),
    ("category", ("missing_category",)),
    ("quantity", ("missing_quantity", "invalid_quantity")),
    ("unit_price", ("missing_unit_price", "invalid_unit_price")),
    ("transaction_date", ("missing_transaction_date", "invalid_transaction_date")),
    ("country", ("missing_country",)),
  ],
)
def test_blank_field_is_missing_and_also_invalid_where_a_format_rule_exists(field, expected, blank):
  assert reasons_of(**{field: blank}) == expected


@pytest.mark.parametrize("value", ["1", "0007", "9" * 18, "100"])
def test_valid_transaction_id(value):
  assert reasons_of(transaction_id=value) == ()


@pytest.mark.parametrize("value", ["0", "000", "-1", "+1", "abc", "1.5", "1" * 19, " 7", "7 ", "٣", "1e3"])
def test_invalid_transaction_id(value):
  assert reasons_of(transaction_id=value) == ("invalid_transaction_id",)


@pytest.mark.parametrize("value", ["1", "9999", "0001", "500"])
def test_valid_quantity(value):
  assert reasons_of(quantity=value) == ()


@pytest.mark.parametrize("value", ["0", "10000", "-1", "+5", "1.5", "abc", "٣", " 5", "5 ", "1e2"])
def test_invalid_quantity(value):
  assert reasons_of(quantity=value) == ("invalid_quantity",)


@pytest.mark.parametrize("value", ["10", "10.5", "10.50", "+5.00", "0.01", "9999999.99", "1234567"])
def test_valid_unit_price(value):
  assert reasons_of(unit_price=value) == ()


@pytest.mark.parametrize(
  "value",
  ["1.234", "abc", "12345678.00", ".5", "5.", "1e3", "1,50", " 5.00", "5.00 ", "--5", "٣.٠٠", "1.2.3"],
)
def test_malformed_unit_price_has_only_the_format_code(value):
  assert reasons_of(unit_price=value) == ("invalid_unit_price",)


@pytest.mark.parametrize("value", ["-5.00", "0.00", "0", "-0", "+0.0", "-12.5", "-0.01", "-9999999.99"])
def test_non_positive_unit_price_has_only_its_own_code(value):
  assert reasons_of(unit_price=value) == ("non_positive_unit_price",)


@pytest.mark.parametrize("value", ["2025-02-21", "2024-02-29", "2025-12-31", "1999-01-01", "2025-01-01"])
def test_valid_transaction_date(value):
  assert reasons_of(transaction_date=value) == ()


@pytest.mark.parametrize(
  "value",
  [
    "2025-02-30",
    "2025-13-01",
    "2025-00-10",
    "2025-04-31",
    "2023-02-29",
    "0000-01-01",
    "2025-1-1",
    "20250101",
    "2025/01/01",
    "01-02-2025",
    "2025-02-21 ",
    "٢٠٢٥-٠١-٠١",
    "2025-02-21T10:00:00",
  ],
)
def test_invalid_transaction_date(value):
  assert reasons_of(transaction_date=value) == ("invalid_transaction_date",)


def test_every_failure_of_a_row_is_collected_in_catalog_order():
  reasons = reasons_of(quantity="0", transaction_date="nope", product="", unit_price="-1.00")

  assert reasons == (
    "missing_product",
    "invalid_quantity",
    "non_positive_unit_price",
    "invalid_transaction_date",
  )
  assert list(reasons) == [code for code in REASON_CODES if code in reasons]


def test_rejection_keeps_the_original_values_and_record_number():
  _, bad, _ = rows = numbered(GOOD, GOOD | {"unit_price": "1.234"}, GOOD)

  result = validate(extracted(*rows))

  assert len(result.rejected) == 1
  rejection = result.rejected[0]
  assert rejection.record_number == 3
  assert rejection.values == tuple(bad[name] for name in REQUIRED_COLUMNS)
  assert result.valid.index.tolist() == [2, 4]


def test_wrong_column_count_rows_carry_only_that_code_and_their_values():
  short = MalformedRow(3, ("1", "short"))
  long = MalformedRow(5, (*GOOD.values(), "extra"))

  result = validate(extracted(*numbered(GOOD, GOOD), malformed=[short, long]))

  assert [(r.record_number, r.reasons, r.values) for r in result.rejected] == [
    (3, ("wrong_column_count",), ("1", "short")),
    (5, ("wrong_column_count",), (*GOOD.values(), "extra")),
  ]


def test_rejections_are_ordered_by_record_number_across_both_sources():
  bad = GOOD | {"quantity": "0"}
  malformed = [MalformedRow(4, ("x",))]

  result = validate(extracted(*numbered(GOOD, bad, GOOD, bad), malformed=malformed))

  assert [r.record_number for r in result.rejected] == [3, 4, 5]


def test_empty_input_validates_to_nothing():
  result = validate(extracted())

  assert result.valid.empty
  assert result.rejected == ()


def test_valid_plus_rejected_equals_input():
  bad = GOOD | {"quantity": "0"}
  data = extracted(*numbered(GOOD, bad, GOOD), malformed=[MalformedRow(5, ("x",))])

  result = validate(data)

  assert len(result.valid) + len(result.rejected) == data.rows_in


def test_clean_dataset_has_no_rejections():
  result = validate(extract(DATA_DIR / "sales_valid.csv", 50 * 1024 * 1024))

  assert result.rejected == ()
  assert len(result.valid) == 1000


def duplicates_of(*ids: str) -> list[int]:
  result = validate(ids_extracted(*ids))
  return [r.record_number for r in result.rejected if "duplicate_transaction_id" in r.reasons]


def test_second_occurrence_of_an_identifier_is_the_duplicate():
  assert duplicates_of("5", "6", "5") == [4]


def test_first_occurrence_wins_and_every_later_one_is_rejected():
  assert duplicates_of("5", "5", "6", "5") == [3, 5]


def test_identifiers_are_compared_without_leading_zeros():
  assert duplicates_of("7", "0007", "00007") == [3, 4]
  assert duplicates_of("0007", "7") == [3]


def test_duplicate_row_carries_only_the_duplicate_code_when_otherwise_valid():
  result = validate(ids_extracted("5", "5"))

  assert [(r.record_number, r.reasons) for r in result.rejected] == [(3, ("duplicate_transaction_id",))]
  assert result.valid.index.tolist() == [2]


def test_first_occurrence_wins_even_when_that_row_is_invalid_for_another_reason():
  data = extracted(GOOD | {"quantity": "0"}, GOOD)

  result = validate(data)

  assert [(r.record_number, r.reasons) for r in result.rejected] == [
    (2, ("invalid_quantity",)),
    (3, ("duplicate_transaction_id",)),
  ]


def test_duplicate_combines_with_the_other_codes_of_the_row():
  data = extracted(GOOD, GOOD | {"quantity": "0"})

  assert validate(data).rejected[0].reasons == ("invalid_quantity", "duplicate_transaction_id")


@pytest.mark.parametrize("bad_id", ["abc", "0", "00", "", "1" * 19, "-5"])
def test_malformed_identifiers_never_count_as_duplicates(bad_id):
  assert duplicates_of(bad_id, bad_id, bad_id) == []


def test_a_malformed_identifier_does_not_shadow_a_later_valid_one():
  assert duplicates_of("abc", "5", "5") == [4]


def test_valid_duplicate_free_identifiers_are_all_kept():
  result = validate(ids_extracted("1", "2", "3", "10", "20"))

  assert result.rejected == ()
  assert len(result.valid) == 5


def test_defective_dataset_yields_exactly_its_12_planted_rejections():
  result = validate(extract(DATA_DIR / "sales_defective.csv", 50 * 1024 * 1024))

  breakdown = Counter(code for rejection in result.rejected for code in rejection.reasons)
  assert breakdown == {
    "non_positive_unit_price": 3,
    "missing_product": 2,
    "duplicate_transaction_id": 2,
    "invalid_transaction_date": 2,
    "invalid_quantity": 2,
    "invalid_unit_price": 1,
  }
  assert len(result.rejected) == 12
  assert len(result.valid) == 988


CODE_TRIGGERS = {
  "missing_transaction_id": {"transaction_id": ""},
  "invalid_transaction_id": {"transaction_id": "abc"},
  "missing_product": {"product": " "},
  "missing_category": {"category": ""},
  "missing_quantity": {"quantity": ""},
  "invalid_quantity": {"quantity": "0"},
  "missing_unit_price": {"unit_price": ""},
  "invalid_unit_price": {"unit_price": "1.234"},
  "non_positive_unit_price": {"unit_price": "0.00"},
  "missing_transaction_date": {"transaction_date": ""},
  "invalid_transaction_date": {"transaction_date": "2025-02-30"},
  "missing_country": {"country": ""},
}


def test_every_reason_code_has_a_triggering_example():
  triggered = {code for overrides in CODE_TRIGGERS.values() for code in reasons_of(**overrides)}
  triggered |= {r for rejection in validate(ids_extracted("1", "1")).rejected for r in rejection.reasons}
  triggered |= {
    reason
    for rejection in validate(extracted(malformed=[MalformedRow(2, ("x",))])).rejected
    for reason in rejection.reasons
  }

  assert triggered == set(REASON_CODES)


@pytest.mark.parametrize(("code", "overrides"), CODE_TRIGGERS.items())
def test_each_trigger_example_produces_its_own_code(code, overrides):
  assert code in reasons_of(**overrides)


def test_one_short_and_one_long_row_are_rejected_and_the_rest_load(tmp_path):
  header = ",".join(REQUIRED_COLUMNS)
  good = ",".join(GOOD.values())
  path = tmp_path / "ragged.csv"
  path.write_text(
    f"{header}\n{good}\n1,short\n{good.replace('1,', '2,', 1)}\n{good},extra\n", encoding="utf-8"
  )

  result = validate(extract(path, 1024 * 1024))

  assert [(r.record_number, r.reasons) for r in result.rejected] == [
    (3, ("wrong_column_count",)),
    (5, ("wrong_column_count",)),
  ]
  assert len(result.valid) == 2


def test_header_only_file_validates_to_nothing(tmp_path):
  path = tmp_path / "empty.csv"
  path.write_text(",".join(REQUIRED_COLUMNS) + "\n", encoding="utf-8")

  result = validate(extract(path, 1024))

  assert result.rejected == ()
  assert result.valid.empty
