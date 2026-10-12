from datetime import date
from decimal import Decimal

import pytest

from source.load import LoadCounts, insert_sales
from source.transform import Sale

BASE_ID = 900_000_000_000


def sale(offset, product="Widget"):
  return Sale(
    transaction_id=BASE_ID + offset,
    product=product,
    category="Tools",
    quantity=3,
    unit_price=Decimal("6.10"),
    total=Decimal("18.30"),
    transaction_date=date(2025, 1, 2),
    country="Peru",
  )


def count_sales(conn, run_id):
  return conn.execute("SELECT count(*) FROM sales WHERE loaded_by_run = %s", (run_id,)).fetchone()[0]


@pytest.mark.integration
def test_new_sales_are_inserted_and_tagged_with_the_run(conn, make_run):
  run_id = make_run("load-new")

  counts = insert_sales(conn, run_id, [sale(1), sale(2), sale(3)])

  assert counts == LoadCounts(loaded=3, skipped_existing=0)
  assert count_sales(conn, run_id) == 3
  stored = conn.execute(
    "SELECT unit_price, total FROM sales WHERE transaction_id = %s", (BASE_ID + 1,)
  ).fetchone()
  assert stored == (Decimal("6.10"), Decimal("18.30"))


@pytest.mark.integration
def test_rerun_skips_every_existing_sale_and_changes_nothing(conn, make_run):
  first, second = make_run("load-first"), make_run("load-second")
  sales = [sale(11), sale(12)]
  insert_sales(conn, first, sales)

  counts = insert_sales(conn, second, sales)

  assert counts == LoadCounts(loaded=0, skipped_existing=2)
  assert count_sales(conn, first) == 2
  assert count_sales(conn, second) == 0


@pytest.mark.integration
def test_mixed_batch_separates_inserted_from_existing(conn, make_run):
  first, second = make_run("load-mixed-a"), make_run("load-mixed-b")
  insert_sales(conn, first, [sale(21)])

  counts = insert_sales(conn, second, [sale(21), sale(22), sale(23)])

  assert counts == LoadCounts(loaded=2, skipped_existing=1)


@pytest.mark.integration
def test_existing_identifier_with_different_values_is_skipped_not_updated(conn, make_run):
  first, second = make_run("load-diff-a"), make_run("load-diff-b")
  insert_sales(conn, first, [sale(31, product="Original")])

  counts = insert_sales(conn, second, [sale(31, product="Changed")])

  assert counts == LoadCounts(loaded=0, skipped_existing=1)
  product = conn.execute("SELECT product FROM sales WHERE transaction_id = %s", (BASE_ID + 31,)).fetchone()
  assert product == ("Original",)


@pytest.mark.integration
def test_empty_batch_loads_nothing(conn, make_run):
  assert insert_sales(conn, make_run("load-empty"), []) == LoadCounts(loaded=0, skipped_existing=0)


@pytest.mark.integration
def test_failure_inside_the_caller_transaction_rolls_every_insert_back(conn, make_run):
  run_id = make_run("load-rollback")

  with pytest.raises(RuntimeError):
    with conn.transaction():
      insert_sales(conn, run_id, [sale(41), sale(42)])
      raise RuntimeError("reconciliation mismatch")

  assert count_sales(conn, run_id) == 0
