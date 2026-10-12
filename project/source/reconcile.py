from collections.abc import Sequence

import psycopg

from source.audit import RunError
from source.load import LoadCounts


class ReconciliationError(RunError):
  pass


def reconcile(
  conn: psycopg.Connection,
  run_id: str,
  *,
  rows_in: int,
  rows_valid: int,
  rows_rejected: int,
  load: LoadCounts,
  transaction_ids: Sequence[int],
) -> None:
  problems = []
  if rows_in != rows_valid + rows_rejected:
    problems.append(
      f"rows_in {rows_in} differs from rows_valid {rows_valid} plus rows_rejected {rows_rejected}"
    )
  if rows_valid != load.loaded + load.skipped_existing:
    problems.append(
      f"rows_valid {rows_valid} differs from rows_loaded {load.loaded} plus "
      f"rows_skipped_existing {load.skipped_existing}"
    )
  present = _count(
    conn, "SELECT count(*) FROM sales WHERE transaction_id = ANY(%s::bigint[])", (list(transaction_ids),)
  )
  if present != rows_valid:
    problems.append(f"{present} batch identifiers found in sales, expected {rows_valid}")
  tagged = _count(conn, "SELECT count(*) FROM sales WHERE loaded_by_run = %s", (run_id,))
  if tagged != load.loaded:
    problems.append(f"{tagged} sales tagged with this run, expected {load.loaded}")
  if problems:
    raise ReconciliationError("reconciliation failed: " + "; ".join(problems))


def _count(conn: psycopg.Connection, query: str, params: tuple) -> int:
  return conn.execute(query, params).fetchone()[0]
