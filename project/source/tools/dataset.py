import csv
import random
from datetime import date, timedelta
from decimal import Decimal
from pathlib import Path

from source.ingest.reader import REQUIRED_COLUMNS

CLEAN_FILE = "sales_valid.csv"
DEFECTIVE_FILE = "sales_defective.csv"
CLEAN_SEED = 20250101
DEFECTIVE_SEED = CLEAN_SEED + 1
CLEAN_FIRST_ID = 1
DEFECTIVE_FIRST_ID = 10001
ROWS_PER_FILE = 1000
MESSY_SHARE = 0.08
YEAR = 2025

CATALOG = {
  "Electronics": [
    ("Wireless Mouse", "24.90"),
    ("USB-C Cable", "9.50"),
    ("Bluetooth Speaker", "59.99"),
    ("Laptop Stand", "34.00"),
    ("Webcam HD", "49.90"),
  ],
  "Home": [
    ("Desk Lamp", "27.45"),
    ("Coffee Maker", "89.00"),
    ("Throw Pillow", "15.75"),
    ("Wall Clock", "21.30"),
    ("Storage Box", "12.99"),
  ],
  "Sports": [
    ("Yoga Mat", "19.90"),
    ("Water Bottle", "11.25"),
    ("Jump Rope", "8.40"),
    ("Dumbbell Set", "64.00"),
    ("Running Belt", "17.60"),
  ],
  "Office": [
    ("Notebook A5", "3.80"),
    ("Ballpoint Pens", "5.25"),
    ("Desk Organizer", "16.40"),
    ("Stapler", "7.95"),
    ("Whiteboard Markers", "6.70"),
  ],
  "Toys": [
    ("Building Blocks", "29.99"),
    ("Puzzle 500", "13.50"),
    ("Board Game", "38.00"),
    ("Plush Bear", "18.25"),
    ("Toy Car", "9.99"),
  ],
}
COUNTRIES = [
  "Colombia",
  "Mexico",
  "Spain",
  "United States",
  "Germany",
  "Brazil",
  "Chile",
  "Peru",
  "Argentina",
  "France",
]

# Planted defects of the defective file: zero-based row position -> replacement value (or the position
# of the row whose identifier is copied, for duplicates). Each row carries exactly one defect.
NON_POSITIVE_PRICES = {120: "-5.00", 480: "0.00", 760: "-12.50"}
MISSING_PRODUCTS = (205, 640)
DUPLICATE_IDS = {330: 10, 880: 500}
INVALID_DATES = {55: "2025-02-30", 910: "2025-13-01"}
INVALID_QUANTITIES = {410: "0", 690: "abc"}
MALFORMED_PRICES = {999: "1.234"}

Row = list[str]


def generate_datasets(directory: Path) -> tuple[Path, Path]:
  directory.mkdir(parents=True, exist_ok=True)
  clean = directory / CLEAN_FILE
  defective = directory / DEFECTIVE_FILE
  _write(clean, clean_rows())
  _write(defective, defective_rows())
  return clean, defective


def clean_rows() -> list[Row]:
  return _build_rows(CLEAN_FIRST_ID, ROWS_PER_FILE, random.Random(CLEAN_SEED))


def defective_rows() -> list[Row]:
  rows = _build_rows(DEFECTIVE_FIRST_ID, ROWS_PER_FILE, random.Random(DEFECTIVE_SEED))
  column = {name: position for position, name in enumerate(REQUIRED_COLUMNS)}
  for position, value in NON_POSITIVE_PRICES.items():
    rows[position][column["unit_price"]] = value
  for position in MISSING_PRODUCTS:
    rows[position][column["product"]] = ""
  for position, source in DUPLICATE_IDS.items():
    rows[position][column["transaction_id"]] = rows[source][column["transaction_id"]]
  for position, value in INVALID_DATES.items():
    rows[position][column["transaction_date"]] = value
  for position, value in INVALID_QUANTITIES.items():
    rows[position][column["quantity"]] = value
  for position, value in MALFORMED_PRICES.items():
    rows[position][column["unit_price"]] = value
  return rows


def _build_rows(first_id: int, count: int, rng: random.Random) -> list[Row]:
  rows = []
  for offset in range(count):
    category = rng.choice(list(CATALOG))
    product, base_price = rng.choice(CATALOG[category])
    price = (Decimal(base_price) * Decimal(rng.randint(90, 110)) / 100).quantize(Decimal("0.01"))
    day = date(YEAR, 1, 1) + timedelta(days=rng.randrange(365))
    country = rng.choice(COUNTRIES)
    if rng.random() < MESSY_SHARE:
      product, category, country = (_messy(value, rng) for value in (product, category, country))
    rows.append(
      [
        str(first_id + offset),
        product,
        category,
        str(rng.randint(1, 20)),
        str(price),
        day.isoformat(),
        country,
      ]
    )
  return rows


def _messy(text: str, rng: random.Random) -> str:
  """Valid but untidy text, so the transform has visible work."""
  style = rng.choice(["upper", "lower", "padded", "spaced"])
  if style == "upper":
    return text.upper()
  if style == "lower":
    return text.lower()
  if style == "padded":
    return f"  {text} "
  return text.replace(" ", "   ") if " " in text else f" {text.lower()}"


def _write(path: Path, rows: list[Row]) -> None:
  with path.open("w", newline="", encoding="utf-8") as handle:
    writer = csv.writer(handle, lineterminator="\n")
    writer.writerow(REQUIRED_COLUMNS)
    writer.writerows(rows)
