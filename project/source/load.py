from collections.abc import Sequence
from dataclasses import dataclass

import psycopg

from source.transform import Sale

INSERT_SALE = """
  INSERT INTO sales (transaction_id, product, category, quantity, unit_price, total,
                     transaction_date, country, loaded_by_run)
  VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
  ON CONFLICT (transaction_id) DO NOTHING
"""


@dataclass(frozen=True)
class LoadCounts:
  loaded: int
  skipped_existing: int


def insert_sales(conn: psycopg.Connection, run_id: str, sales: Sequence[Sale]) -> LoadCounts:
  loaded = 0
  with conn.cursor() as cursor:
    for sale in sales:
      cursor.execute(
        INSERT_SALE,
        (
          sale.transaction_id,
          sale.product,
          sale.category,
          sale.quantity,
          sale.unit_price,
          sale.total,
          sale.transaction_date,
          sale.country,
          run_id,
        ),
      )
      if cursor.rowcount not in (0, 1):
        raise RuntimeError(f"unexpected affected row count: {cursor.rowcount}")
      loaded += cursor.rowcount
  return LoadCounts(loaded=loaded, skipped_existing=len(sales) - loaded)
