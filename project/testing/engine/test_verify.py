from datetime import date
from decimal import Decimal

import pytest

from source.engine.verify import ReconciliationError, reconcile
from source.ingest.shaper import Sale
from source.storage.sales import LoadCounts, insert_sales

BASE_ID = 800_000_000_000


def sale(offset):
  return Sale(
    transaction_id=BASE_ID + offset,
    product="Widget",
    category="Tools",
    quantity=2,
    unit_price=Decimal("1.50"),
    total=Decimal("3.00"),
    transaction_date=date(2025, 1, 2),
    country="Peru",
  )


def load(conn, run_id, sales):
  counts = insert_sales(conn, run_id, sales)
  return counts, [item.transaction_id for item in sales]


@pytest.mark.integration
def test_consistent_counts_reconcile(conn, make_run):
  run_id = make_run("reconcile-ok")
  counts, ids = load(conn, run_id, [sale(1), sale(2)])

  reconcile(conn, run_id, rows_in=3, rows_valid=2, rows_rejected=1, load=counts, transaction_ids=ids)


@pytest.mark.integration
def test_skipped_existing_sales_still_reconcile(conn, make_run):
  first, second = make_run("reconcile-first"), make_run("reconcile-second")
  load(conn, first, [sale(11)])
  counts, ids = load(conn, second, [sale(11), sale(12)])

  reconcile(conn, second, rows_in=2, rows_valid=2, rows_rejected=0, load=counts, transaction_ids=ids)


@pytest.mark.integration
def test_empty_batch_reconciles(conn, make_run):
  run_id = make_run("reconcile-empty")

  reconcile(conn, run_id, rows_in=0, rows_valid=0, rows_rejected=0, load=LoadCounts(0, 0), transaction_ids=[])


@pytest.mark.integration
def test_input_not_equal_to_valid_plus_rejected_fails(conn, make_run):
  run_id = make_run("reconcile-input")
  counts, ids = load(conn, run_id, [sale(21)])

  with pytest.raises(ReconciliationError, match="rows_in 5"):
    reconcile(conn, run_id, rows_in=5, rows_valid=1, rows_rejected=1, load=counts, transaction_ids=ids)


@pytest.mark.integration
def test_valid_not_equal_to_loaded_plus_skipped_fails(conn, make_run):
  run_id = make_run("reconcile-valid")
  counts, ids = load(conn, run_id, [sale(31), sale(32)])

  with pytest.raises(ReconciliationError, match="rows_valid 3"):
    reconcile(conn, run_id, rows_in=3, rows_valid=3, rows_rejected=0, load=counts, transaction_ids=ids)


@pytest.mark.integration
def test_skipped_row_that_is_not_in_the_database_fails(conn, make_run):
  run_id = make_run("reconcile-missing")
  load(conn, run_id, [sale(41)])

  with pytest.raises(ReconciliationError, match="batch identifiers"):
    reconcile(
      conn,
      run_id,
      rows_in=2,
      rows_valid=2,
      rows_rejected=0,
      load=LoadCounts(1, 1),
      transaction_ids=[BASE_ID + 41, BASE_ID + 99],
    )


@pytest.mark.integration
def test_reported_loaded_count_that_differs_from_tagged_sales_fails(conn, make_run):
  first, second = make_run("reconcile-tag-a"), make_run("reconcile-tag-b")
  load(conn, first, [sale(51)])
  ids = [BASE_ID + 51]

  with pytest.raises(ReconciliationError, match="tagged with this run"):
    reconcile(
      conn, second, rows_in=1, rows_valid=1, rows_rejected=0, load=LoadCounts(1, 0), transaction_ids=ids
    )
