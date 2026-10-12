import csv
from collections.abc import Sequence
from pathlib import Path

import psycopg
from psycopg.types.json import Jsonb

from source.extract import REQUIRED_COLUMNS
from source.validate import WRONG_COLUMN_COUNT, Rejection

FORMULA_PREFIXES = ("=", "+", "-", "@", "\t", "\r")
UNMAPPED_COLUMN = "unmapped_values"
CSV_HEADER = ("record_number", "reasons", *REQUIRED_COLUMNS, UNMAPPED_COLUMN)

INSERT_REJECTED = "INSERT INTO rejected_records (run_id, record_number, reasons, raw) VALUES (%s, %s, %s, %s)"


def persist_rejections(conn: psycopg.Connection, run_id: str, rejections: Sequence[Rejection]) -> None:
  if not rejections:
    return
  rows = [(run_id, item.record_number, list(item.reasons), Jsonb(_raw(item))) for item in rejections]
  with conn.transaction(), conn.cursor() as cursor:
    cursor.executemany(INSERT_REJECTED, rows)


def write_rejected_csv(reports_dir: Path, run_id: str, rejections: Sequence[Rejection]) -> Path | None:
  if not rejections:
    return None
  reports_dir.mkdir(parents=True, exist_ok=True)
  path = reports_dir / f"{run_id}_rejected.csv"
  with path.open("w", encoding="utf-8", newline="") as handle:
    writer = csv.writer(handle)
    writer.writerow(CSV_HEADER)
    for item in rejections:
      writer.writerow(neutralize(cell) for cell in _csv_cells(item))
  return path


def neutralize(cell: str) -> str:
  return f"'{cell}" if cell.startswith(FORMULA_PREFIXES) else cell


def _raw(item: Rejection) -> dict[str, str] | list[str]:
  if WRONG_COLUMN_COUNT in item.reasons:
    return list(item.values)
  return dict(zip(REQUIRED_COLUMNS, item.values, strict=True))


def _csv_cells(item: Rejection) -> list[str]:
  reasons = ";".join(item.reasons)
  if WRONG_COLUMN_COUNT in item.reasons:
    return [str(item.record_number), reasons, *[""] * len(REQUIRED_COLUMNS), "|".join(item.values)]
  return [str(item.record_number), reasons, *item.values, ""]
