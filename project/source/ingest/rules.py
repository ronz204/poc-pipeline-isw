import re
from collections.abc import Callable
from dataclasses import dataclass
from datetime import date
from decimal import Decimal

import pandas as pd
import pandera.pandas as pa

from source.ingest.reader import REQUIRED_COLUMNS, Extracted

WRONG_COLUMN_COUNT = "wrong_column_count"
DUPLICATE_ID = "duplicate_transaction_id"

ID_PATTERN = re.compile(r"[0-9]{1,18}")
QUANTITY_PATTERN = re.compile(r"0*[1-9][0-9]{0,3}")
PRICE_PATTERN = re.compile(r"[+-]?[0-9]{1,7}(\.[0-9]{1,2})?")
DATE_PATTERN = re.compile(r"([0-9]{4})-([0-9]{2})-([0-9]{2})")

Predicate = Callable[[str], bool]


@dataclass(frozen=True)
class Rejection:
  record_number: int
  reasons: tuple[str, ...]
  values: tuple[str, ...]


@dataclass(frozen=True)
class Validation:
  valid: pd.DataFrame
  rejected: tuple[Rejection, ...]


def _present(value: str) -> bool:
  return value.strip() != ""


def _valid_id(value: str) -> bool:
  return bool(ID_PATTERN.fullmatch(value)) and any(digit != "0" for digit in value)


def _valid_quantity(value: str) -> bool:
  return bool(QUANTITY_PATTERN.fullmatch(value))


def _valid_price(value: str) -> bool:
  return bool(PRICE_PATTERN.fullmatch(value))


def _positive_price(value: str) -> bool:
  return not _valid_price(value) or Decimal(value) > 0


def _valid_date(value: str) -> bool:
  if not (match := DATE_PATTERN.fullmatch(value)):
    return False
  try:
    date(*map(int, match.groups()))
  except ValueError:
    return False
  return True


# Each rule is (column, reason code, predicate that is True when the value passes). The reason code
# is the pandera check name. Order here is the order codes are listed on a rejected row.
RULES: tuple[tuple[str, str, Predicate], ...] = (
  ("transaction_id", "missing_transaction_id", _present),
  ("transaction_id", "invalid_transaction_id", _valid_id),
  ("product", "missing_product", _present),
  ("category", "missing_category", _present),
  ("quantity", "missing_quantity", _present),
  ("quantity", "invalid_quantity", _valid_quantity),
  ("unit_price", "missing_unit_price", _present),
  ("unit_price", "invalid_unit_price", _valid_price),
  ("unit_price", "non_positive_unit_price", _positive_price),
  ("transaction_date", "missing_transaction_date", _present),
  ("transaction_date", "invalid_transaction_date", _valid_date),
  ("country", "missing_country", _present),
)
REASON_CODES = (WRONG_COLUMN_COUNT, *(code for _, code, _ in RULES), DUPLICATE_ID)


def _check(code: str, predicate: Predicate) -> pa.Check:
  def run(column: pd.Series) -> pd.Series:
    return pd.Series([predicate(value) for value in column], index=column.index, dtype=bool)

  return pa.Check(run, name=code)


def _first_occurrence(column: pd.Series) -> pd.Series:
  """True unless the identifier already appeared earlier. Only format-valid identifiers take part, and
  they are compared without leading zeros, so an invalid first row never shadows a later valid one."""
  well_formed = pd.Series([_valid_id(value) for value in column], index=column.index, dtype=bool)
  keys = column[well_formed].map(lambda value: value.lstrip("0"))
  repeated = keys.duplicated(keep="first").reindex(column.index, fill_value=False)
  return ~repeated.astype(bool)


SCHEMA = pa.DataFrameSchema(
  {
    name: pa.Column(
      checks=[
        *(_check(code, predicate) for column, code, predicate in RULES if column == name),
        *([pa.Check(_first_occurrence, name=DUPLICATE_ID)] if name == "transaction_id" else []),
      ]
    )
    for name in REQUIRED_COLUMNS
  }
)


def validate(extracted: Extracted) -> Validation:
  failed = _failed_codes(extracted.rows)
  rejected = [Rejection(row.record_number, (WRONG_COLUMN_COUNT,), row.values) for row in extracted.malformed]
  rejected += [
    Rejection(
      record_number,
      tuple(code for code in REASON_CODES if code in codes),
      tuple(extracted.rows.loc[record_number]),
    )
    for record_number, codes in failed.items()
  ]
  rejected.sort(key=lambda rejection: rejection.record_number)
  valid = extracted.rows.drop(index=list(failed))
  return Validation(valid=valid, rejected=tuple(rejected))


def _failed_codes(rows: pd.DataFrame) -> dict[int, set[str]]:
  failed: dict[int, set[str]] = {}
  try:
    SCHEMA.validate(rows, lazy=True)
  except pa.errors.SchemaErrors as error:
    for index, code in zip(error.failure_cases["index"], error.failure_cases["check"], strict=True):
      if pd.isna(index):
        raise RuntimeError(f"validation failure without a row: {code}") from None
      failed.setdefault(int(index), set()).add(code)
  return failed
