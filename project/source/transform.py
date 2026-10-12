from dataclasses import dataclass
from datetime import date
from decimal import Decimal

import pandas as pd

CENTS = Decimal("0.01")


@dataclass(frozen=True)
class Sale:
  transaction_id: int
  product: str
  category: str
  quantity: int
  unit_price: Decimal
  total: Decimal
  transaction_date: date
  country: str


def transform(valid: pd.DataFrame) -> list[Sale]:
  return [
    _sale(
      transaction_id=row.transaction_id,
      product=row.product,
      category=row.category,
      quantity=row.quantity,
      unit_price=row.unit_price,
      transaction_date=row.transaction_date,
      country=row.country,
    )
    for row in valid.itertuples(index=False)
  ]


def _sale(
  *,
  transaction_id: str,
  product: str,
  category: str,
  quantity: str,
  unit_price: str,
  transaction_date: str,
  country: str,
) -> Sale:
  quantity_value = int(quantity)
  price = Decimal(unit_price).quantize(CENTS)
  return Sale(
    transaction_id=int(transaction_id),
    product=_collapse(product),
    category=_capitalize_words(category),
    quantity=quantity_value,
    unit_price=price,
    total=quantity_value * price,
    transaction_date=date.fromisoformat(transaction_date),
    country=_capitalize_words(country),
  )


def _collapse(text: str) -> str:
  return " ".join(text.split())


def _capitalize_words(text: str) -> str:
  """Capitalize each whitespace-separated word. Splitting on whitespace only keeps apostrophes and
  hyphens from starting a new word, which standard title-casing gets wrong."""
  return " ".join(word.capitalize() for word in text.split())
