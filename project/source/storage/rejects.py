from collections.abc import Sequence

import psycopg
from psycopg.types.json import Jsonb

from source.ingest.reader import REQUIRED_COLUMNS
from source.ingest.rules import Rejection

INSERT_REJECTED = "INSERT INTO rejected_records (run_id, record_number, reasons, raw) VALUES (%s, %s, %s, %s)"


def persist_rejections(conn: psycopg.Connection, run_id: str, rejections: Sequence[Rejection]) -> None:
  if not rejections:
    return
  rows = [(run_id, item.record_number, list(item.reasons), Jsonb(_raw(item))) for item in rejections]
  with conn.transaction(), conn.cursor() as cursor:
    cursor.executemany(INSERT_REJECTED, rows)


def _raw(item: Rejection) -> dict[str, str] | list[str]:
  if item.unmapped:
    return list(item.values)
  return dict(zip(REQUIRED_COLUMNS, item.values, strict=True))
