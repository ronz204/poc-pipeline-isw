import csv
from collections.abc import Sequence
from pathlib import Path

from source.ingest.reader import REQUIRED_COLUMNS
from source.ingest.rules import Rejection

FORMULA_PREFIXES = ("=", "+", "-", "@", "\t", "\r")
UNMAPPED_COLUMN = "unmapped_values"
CSV_HEADER = ("record_number", "reasons", *REQUIRED_COLUMNS, UNMAPPED_COLUMN)


def write_rejected_csv(reports_dir: Path, run_id: str, rejections: Sequence[Rejection]) -> Path | None:
  if not rejections:
    return None
  reports_dir.mkdir(parents=True, exist_ok=True)
  path = reports_dir / f"{run_id}_rejected.csv"
  with path.open("w", encoding="utf-8", newline="") as handle:
    writer = csv.writer(handle)
    writer.writerow(CSV_HEADER)
    for item in rejections:
      writer.writerow(neutralize(cell) for cell in _cells(item))
  return path


def neutralize(cell: str) -> str:
  return f"'{cell}" if cell.startswith(FORMULA_PREFIXES) else cell


def _cells(item: Rejection) -> list[str]:
  reasons = ";".join(item.reasons)
  if item.unmapped:
    return [str(item.record_number), reasons, *[""] * len(REQUIRED_COLUMNS), "|".join(item.values)]
  return [str(item.record_number), reasons, *item.values, ""]
