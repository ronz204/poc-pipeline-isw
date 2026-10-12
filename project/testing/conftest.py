import uuid
from pathlib import Path

import pytest

from source.config.settings import BYTES_PER_MB, DEFAULT_MAX_INPUT_MB, load_settings
from source.storage.connect import connect, ensure_schema


@pytest.fixture
def conn():
  connection = connect(load_settings())
  ensure_schema(connection)
  yield connection
  connection.close()


@pytest.fixture
def make_run(conn):
  created = []

  def create(name):
    run_id = f"test-{name}-{uuid.uuid4().hex[:8]}"
    conn.execute(
      "INSERT INTO etl_runs (run_id, source_file, status, started_at) VALUES (%s, %s, 'RUNNING', now())",
      (run_id, "test.csv"),
    )
    created.append(run_id)
    return run_id

  yield create

  for run_id in created:
    conn.execute("DELETE FROM sales WHERE loaded_by_run = %s", (run_id,))
    conn.execute("DELETE FROM rejected_records WHERE run_id = %s", (run_id,))
    conn.execute("DELETE FROM etl_runs WHERE run_id = %s", (run_id,))


@pytest.fixture(scope="session")
def data_dir():
  return Path(__file__).parents[1] / "data"


@pytest.fixture(scope="session")
def size_cap():
  return int(DEFAULT_MAX_INPUT_MB * BYTES_PER_MB)
