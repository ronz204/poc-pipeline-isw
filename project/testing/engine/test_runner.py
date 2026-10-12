import json
from dataclasses import replace

import pytest

import source.engine.runner as runner_module
from source.config.settings import load_settings
from source.engine.runner import reject_rate_exceeded, run_pipeline
from source.storage.sales import LoadCounts

BASE_ID = 700_000_000_000
HEADER = "transaction_id,product,category,quantity,unit_price,transaction_date,country"


def good_row(offset, product="Zebra Lamp"):
  return f"{BASE_ID + offset},{product},home goods,2,3.50,2025-03-01,peru"


@pytest.fixture
def env(tmp_path, conn):
  settings = replace(load_settings(), reports_dir=tmp_path / "reports", logs_dir=tmp_path / "logs")
  yield settings
  run_ids = [path.stem for path in (tmp_path / "reports").glob("*.json")]
  for run_id in run_ids:
    conn.execute("DELETE FROM sales WHERE loaded_by_run = %s", (run_id,))
    conn.execute("DELETE FROM rejected_records WHERE run_id = %s", (run_id,))
    conn.execute("DELETE FROM etl_runs WHERE run_id = %s", (run_id,))


@pytest.fixture
def write_csv(tmp_path):
  def write(rows, header=HEADER, name="input.csv"):
    path = tmp_path / name
    path.write_text("\n".join([header, *rows]) + "\n", encoding="utf-8")
    return path

  return write


def run_row(conn, run_id):
  return conn.execute(
    "SELECT status, rows_in, rows_valid, rows_rejected, rows_loaded, rows_skipped_existing, error_message "
    "FROM etl_runs WHERE run_id = %s",
    (run_id,),
  ).fetchone()


def sales_count(conn, run_id):
  return conn.execute("SELECT count(*) FROM sales WHERE loaded_by_run = %s", (run_id,)).fetchone()[0]


@pytest.mark.parametrize(
  ("rejected", "rows_in", "threshold", "expected"),
  [
    (2, 10, 0.2, False),
    (3, 10, 0.2, True),
    (3, 10, 0.3, False),
    (7, 10, 0.7, False),
    (1, 3, 0.33, True),
    (0, 0, 0.0, False),
    (0, 10, 0.0, False),
    (1, 10, 0.0, True),
    (10, 10, 1.0, False),
  ],
)
def test_reject_rate_is_exceeded_only_when_strictly_above_the_threshold(
  rejected, rows_in, threshold, expected
):
  assert reject_rate_exceeded(rejected, rows_in, threshold) is expected


@pytest.mark.integration
def test_valid_file_loads_every_row_and_reconciles(conn, env, write_csv):
  report = run_pipeline(write_csv([good_row(i) for i in range(1, 6)]), env)

  assert report.status == "SUCCESS"
  assert (report.rows_in, report.rows_valid, report.rows_rejected) == (5, 5, 0)
  assert (report.rows_loaded, report.rows_skipped_existing) == (5, 0)
  assert report.reconciled is True
  assert report.error is None
  assert sales_count(conn, report.run_id) == 5
  assert run_row(conn, report.run_id) == ("SUCCESS", 5, 5, 0, 5, 0, None)
  assert json.loads((env.reports_dir / f"{report.run_id}.json").read_text()) == report.to_dict()
  assert not (env.reports_dir / f"{report.run_id}_rejected.csv").exists()


@pytest.mark.integration
def test_invalid_rows_are_quarantined_and_the_valid_ones_load(conn, env, write_csv):
  rows = [good_row(i) for i in range(1, 9)]
  rows += [f"{BASE_ID + 9},Secret Gadget,tools,1,-5.00,2025-03-01,peru", f"{BASE_ID + 10},Short Row"]

  report = run_pipeline(write_csv(rows), env)

  assert report.status == "SUCCESS_WITH_REJECTS"
  assert (report.rows_in, report.rows_valid, report.rows_rejected) == (10, 8, 2)
  assert report.rows_loaded == 8
  assert report.rejection_breakdown == {"non_positive_unit_price": 1, "wrong_column_count": 1}
  assert report.reconciled is True
  stored = conn.execute(
    "SELECT record_number, reasons FROM rejected_records WHERE run_id = %s ORDER BY record_number",
    (report.run_id,),
  ).fetchall()
  assert stored == [(10, ["non_positive_unit_price"]), (11, ["wrong_column_count"])]
  assert (env.reports_dir / f"{report.run_id}_rejected.csv").exists()
  log_text = (env.logs_dir / f"{report.run_id}.jsonl").read_text(encoding="utf-8")
  assert "Secret Gadget" not in log_text and "Short Row" not in log_text
  assert "rows_rejected" in log_text


@pytest.mark.integration
def test_rerun_of_the_same_file_loads_nothing_new(conn, env, write_csv):
  path = write_csv([good_row(i) for i in range(1, 6)])

  first = run_pipeline(path, env)
  second = run_pipeline(path, env)

  assert first.rows_loaded == 5
  assert (second.status, second.rows_loaded, second.rows_skipped_existing) == ("SUCCESS", 0, 5)
  assert second.reconciled is True
  assert sales_count(conn, first.run_id) == 5
  assert sales_count(conn, second.run_id) == 0


@pytest.mark.integration
def test_reject_rate_above_the_threshold_fails_before_loading_anything(conn, env, write_csv):
  rows = [good_row(i) for i in range(1, 9)] + [f"{BASE_ID + 9},,tools,1,1.00,2025-03-01,peru", "oops"]
  settings = replace(env, max_reject_rate=0.1)

  report = run_pipeline(write_csv(rows), settings)

  assert report.status == "FAILED"
  assert (report.rows_in, report.rows_valid, report.rows_rejected) == (10, 8, 2)
  assert (report.rows_loaded, report.rows_skipped_existing) == (0, 0)
  assert report.reconciled is False
  assert "reject rate" in report.error
  assert sales_count(conn, report.run_id) == 0
  quarantined = conn.execute(
    "SELECT count(*) FROM rejected_records WHERE run_id = %s", (report.run_id,)
  ).fetchone()[0]
  assert quarantined == 2
  assert run_row(conn, report.run_id)[:6] == ("FAILED", 10, 8, 2, 0, 0)
  assert (env.reports_dir / f"{report.run_id}_rejected.csv").exists()


@pytest.mark.integration
def test_reject_rate_equal_to_the_threshold_passes(env, write_csv):
  rows = [good_row(i) for i in range(1, 9)] + ["oops", "oops again"]

  report = run_pipeline(write_csv(rows), env)

  assert report.status == "SUCCESS_WITH_REJECTS"
  assert report.rows_rejected == 2


@pytest.mark.integration
def test_header_only_file_succeeds_with_zero_counts(conn, env, write_csv):
  report = run_pipeline(write_csv([]), env)

  assert report.status == "SUCCESS"
  assert [report.rows_in, report.rows_valid, report.rows_rejected] == [0, 0, 0]
  assert (report.rows_loaded, report.rows_skipped_existing) == (0, 0)
  assert report.reconciled is True
  assert run_row(conn, report.run_id) == ("SUCCESS", 0, 0, 0, 0, 0, None)


@pytest.mark.integration
def test_missing_required_column_fails_with_null_counts(conn, env, write_csv):
  header = HEADER.replace(",country", "")

  report = run_pipeline(write_csv(["1,a,b,1,1.00,2025-01-01"], header=header), env)

  assert report.status == "FAILED"
  assert "country" in report.error
  assert (report.rows_in, report.rows_valid, report.rows_rejected, report.rows_loaded) == (None,) * 4
  assert report.reconciled is False
  assert run_row(conn, report.run_id) == ("FAILED", None, None, None, None, None, report.error)


@pytest.mark.integration
def test_missing_file_fails_with_null_counts(conn, env, tmp_path):
  report = run_pipeline(tmp_path / "absent.csv", env)

  assert report.status == "FAILED"
  assert "not found" in report.error
  assert report.rows_in is None and report.rows_loaded is None
  assert run_row(conn, report.run_id)[0] == "FAILED"
  assert (env.reports_dir / f"{report.run_id}.json").exists()


@pytest.mark.integration
def test_file_above_the_size_cap_fails_before_reading(env, write_csv):
  report = run_pipeline(write_csv([good_row(1)]), replace(env, max_input_bytes=10))

  assert report.status == "FAILED"
  assert "limit" in report.error
  assert report.rows_in is None


@pytest.mark.integration
def test_database_down_fails_but_still_writes_the_report(conn, env, write_csv):
  settings = replace(env, db_port=1)

  report = run_pipeline(write_csv([good_row(1)]), settings)

  assert report.status == "FAILED"
  assert report.error == "database connection failed"
  assert report.rows_in is None and report.reconciled is False
  assert (env.reports_dir / f"{report.run_id}.json").exists()
  assert conn.execute("SELECT count(*) FROM etl_runs WHERE run_id = %s", (report.run_id,)).fetchone() == (0,)


@pytest.mark.integration
def test_unwritable_logs_directory_fails_with_a_clear_error(env, write_csv, tmp_path):
  blocker = tmp_path / "blocker"
  blocker.write_text("file", encoding="utf-8")

  report = run_pipeline(write_csv([good_row(1)]), replace(env, logs_dir=blocker / "logs"))

  assert report.status == "FAILED"
  assert report.error.startswith("logs directory is not writable")
  assert report.rows_in is None
  assert (env.reports_dir / f"{report.run_id}.json").exists()


@pytest.mark.integration
def test_reconciliation_mismatch_rolls_back_every_insert_of_the_run(conn, env, write_csv, monkeypatch):
  real_insert = runner_module.insert_sales

  def lying_insert(connection, run_id, sales):
    counts = real_insert(connection, run_id, sales)
    return LoadCounts(counts.loaded + 1, counts.skipped_existing)

  monkeypatch.setattr(runner_module, "insert_sales", lying_insert)

  report = run_pipeline(write_csv([good_row(i) for i in range(1, 4)]), env)

  assert report.status == "FAILED"
  assert report.error.startswith("reconciliation failed")
  assert report.reconciled is False
  assert (report.rows_loaded, report.rows_skipped_existing) == (0, 0)
  assert sales_count(conn, report.run_id) == 0
  assert run_row(conn, report.run_id)[0] == "FAILED"
