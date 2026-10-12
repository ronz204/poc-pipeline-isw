import pytest

from source.database import connect, ensure_schema
from source.settings import load_settings

TABLES = {"etl_runs", "sales", "rejected_records"}


@pytest.mark.integration
def test_schema_applies_twice_without_error():
  conn = connect(load_settings())
  try:
    ensure_schema(conn)
    ensure_schema(conn)
    rows = conn.execute(
      "SELECT table_name FROM information_schema.tables WHERE table_schema = %s",
      ("public",),
    ).fetchall()
  finally:
    conn.close()

  assert TABLES <= {name for (name,) in rows}
