from datetime import date
from decimal import Decimal
from pathlib import Path

import pandas as pd
import pytest

from source.ingest.reader import REQUIRED_COLUMNS, extract
from source.ingest.rules import validate
from source.ingest.shaper import Sale, transform

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


def sale_of(**overrides: str) -> Sale:
  row = GOOD | overrides
  frame = pd.DataFrame([[row[name] for name in REQUIRED_COLUMNS]], columns=list(REQUIRED_COLUMNS), dtype=str)
  (sale,) = transform(frame)
  return sale


def test_values_are_converted_to_their_types():
  sale = sale_of()

  assert sale == Sale(
    transaction_id=1,
    product="Toy Car",
    category="Toys",
    quantity=7,
    unit_price=Decimal("10.09"),
    total=Decimal("70.63"),
    transaction_date=date(2025, 2, 21),
    country="Colombia",
  )


def test_empty_input_transforms_to_nothing():
  empty = pd.DataFrame([], columns=list(REQUIRED_COLUMNS), dtype=str)

  assert transform(empty) == []


@pytest.mark.parametrize(
  ("text", "expected"),
  [
    ("  Toy Car ", "Toy Car"),
    ("Toy   \t Car", "Toy Car"),
    (" Toy Car ", "Toy Car"),
    ("TOY CAR", "TOY CAR"),
    ("toy car", "toy car"),
  ],
)
def test_product_is_trimmed_and_collapsed_but_keeps_its_case(text, expected):
  assert sale_of(product=text).product == expected


@pytest.mark.parametrize(
  ("text", "expected"),
  [
    ("  home  ", "Home"),
    ("HOME APPLIANCES", "Home Appliances"),
    ("home   and\tgarden", "Home And Garden"),
    ("united states", "United States"),
  ],
)
@pytest.mark.parametrize("field", ["category", "country"])
def test_category_and_country_are_capitalized_per_word(field, text, expected):
  assert getattr(sale_of(**{field: text}), field) == expected


@pytest.mark.parametrize(
  ("text", "expected"),
  [
    ("cote d'ivoire", "Cote D'ivoire"),
    ("o'brien street", "O'brien Street"),
    ("guinea-bissau", "Guinea-bissau"),
  ],
)
def test_words_are_split_on_whitespace_only(text, expected):
  assert sale_of(country=text).country == expected


@pytest.mark.parametrize(
  ("price", "expected"),
  [
    ("10", "10.00"),
    ("10.5", "10.50"),
    ("10.50", "10.50"),
    ("+5.00", "5.00"),
    ("0.01", "0.01"),
    ("0010.5", "10.50"),
    ("9999999.99", "9999999.99"),
  ],
)
def test_price_is_an_exact_decimal_with_two_places(price, expected):
  sale = sale_of(unit_price=price)

  assert sale.unit_price == Decimal(expected)
  assert str(sale.unit_price) == str(Decimal(expected))


def test_total_is_exact_where_floating_point_is_not():
  sale = sale_of(quantity="3", unit_price="6.10")

  assert sale.total == Decimal("18.30")
  assert str(sale.total) == "18.30"
  assert 3 * 6.10 != 18.30


def test_total_at_the_largest_bounds_fits_the_column():
  sale = sale_of(quantity="9999", unit_price="9999999.99")

  assert sale.total == Decimal("99989999900.01")
  assert len(str(sale.total).replace(".", "")) <= 14


def test_money_is_never_a_float():
  sale = sale_of()

  assert isinstance(sale.unit_price, Decimal)
  assert isinstance(sale.total, Decimal)


def test_identifier_loses_its_leading_zeros_and_quantity_too():
  sale = sale_of(transaction_id="0007", quantity="0003")

  assert (sale.transaction_id, sale.quantity) == (7, 3)


def test_rows_keep_their_order():
  frame = pd.DataFrame(
    [[str(i), "p", "c", "1", "1.00", "2025-01-01", "x"] for i in (5, 3, 9)],
    columns=list(REQUIRED_COLUMNS),
    dtype=str,
  )

  assert [sale.transaction_id for sale in transform(frame)] == [5, 3, 9]


def test_clean_dataset_transforms_to_exact_totals_and_tidy_text():
  sales = transform(validate(extract(DATA_DIR / "sales_valid.csv", 50 * 1024 * 1024)).valid)

  assert len(sales) == 1000
  assert all(sale.total == sale.quantity * sale.unit_price for sale in sales)
  assert all(sale.unit_price == sale.unit_price.quantize(Decimal("0.01")) for sale in sales)
  assert all(sale.category == sale.category.capitalize() for sale in sales)
  assert all(sale.country == " ".join(sale.country.split()) for sale in sales)
  assert all(sale.product == " ".join(sale.product.split()) for sale in sales)
  messy = next(sale for sale in sales if sale.transaction_id == 44)
  assert (messy.product, messy.category, messy.country) == ("Ballpoint Pens", "Office", "Chile")


def test_defective_dataset_transforms_its_988_valid_rows():
  sales = transform(validate(extract(DATA_DIR / "sales_defective.csv", 50 * 1024 * 1024)).valid)

  assert len(sales) == 988
  assert len({sale.transaction_id for sale in sales}) == 988
