import csv
from dataclasses import dataclass
from pathlib import Path

import pandas as pd

REQUIRED_COLUMNS = (
  "transaction_id",
  "product",
  "category",
  "quantity",
  "unit_price",
  "transaction_date",
  "country",
)
FIRST_DATA_RECORD_NUMBER = 2


class ExtractError(ValueError):
  pass


@dataclass(frozen=True)
class MalformedRow:
  record_number: int
  values: tuple[str, ...]


@dataclass(frozen=True)
class Extracted:
  rows: pd.DataFrame
  malformed: tuple[MalformedRow, ...]
  extra_columns: tuple[str, ...]

  @property
  def rows_in(self) -> int:
    return len(self.rows) + len(self.malformed)


def extract(path: Path, max_bytes: int) -> Extracted:
  _check_size(path, max_bytes)
  header, raw_rows = _read_rows(path)
  positions = _required_positions(header)

  records: list[list[str]] = []
  record_numbers: list[int] = []
  malformed: list[MalformedRow] = []
  for offset, cells in enumerate(raw_rows):
    record_number = offset + FIRST_DATA_RECORD_NUMBER
    if not cells:
      cells = [""] * len(header)
    if len(cells) != len(header):
      malformed.append(MalformedRow(record_number, tuple(cells)))
      continue
    records.append([cells[position] for position in positions])
    record_numbers.append(record_number)

  rows = pd.DataFrame(records, columns=list(REQUIRED_COLUMNS), index=record_numbers, dtype=str)
  extra_columns = tuple(name for name in header if name not in REQUIRED_COLUMNS)
  return Extracted(rows=rows, malformed=tuple(malformed), extra_columns=extra_columns)


def _check_size(path: Path, max_bytes: int) -> None:
  try:
    size = path.stat().st_size
  except FileNotFoundError:
    raise ExtractError(f"input file not found: {path}") from None
  except OSError as error:
    raise ExtractError(f"input file cannot be read: {path} ({error.strerror})") from None
  if size > max_bytes:
    raise ExtractError(f"input file is {size} bytes, above the {max_bytes} byte limit")


def _read_rows(path: Path) -> tuple[list[str], list[list[str]]]:
  try:
    with path.open(encoding="utf-8-sig", newline="") as handle:
      reader = csv.reader(handle)
      header = next(reader, None)
      if header is None:
        raise ExtractError("input file is empty: the header line is missing")
      return header, list(reader)
  except UnicodeDecodeError:
    raise ExtractError("input file is not valid UTF-8") from None
  except csv.Error as error:
    raise ExtractError(f"input file is not readable as CSV: {error}") from None
  except OSError as error:
    raise ExtractError(f"input file cannot be read: {path} ({error.strerror})") from None


def _required_positions(header: list[str]) -> list[int]:
  missing = [name for name in REQUIRED_COLUMNS if name not in header]
  if missing:
    raise ExtractError(f"missing required columns: {', '.join(missing)}")
  return [header.index(name) for name in REQUIRED_COLUMNS]
