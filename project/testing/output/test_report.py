import json

from source.engine.status import FAILED, SUCCESS, RunResult
from source.output.report import to_markdown, write_json

RUN_ID = "20250101T120000-a1b2c3"


def success_result():
  return RunResult(
    run_id=RUN_ID,
    source_file="data/sales_valid.csv",
    status=SUCCESS,
    rows_in=1000,
    rows_valid=1000,
    rows_rejected=0,
    rows_loaded=1000,
    rows_skipped_existing=0,
    reconciled=True,
    duration_ms=12,
  )


def failed_early_result():
  return RunResult(
    run_id=RUN_ID,
    source_file="data/missing.csv",
    status=FAILED,
    duration_ms=3,
    error="input file not found: data/missing.csv",
  )


def test_json_has_the_documented_shape(tmp_path):
  data = json.loads(write_json(success_result(), tmp_path).read_text(encoding="utf-8"))

  assert data == {
    "run_id": RUN_ID,
    "source_file": "data/sales_valid.csv",
    "status": "SUCCESS",
    "rows_in": 1000,
    "rows_valid": 1000,
    "rows_rejected": 0,
    "rows_loaded": 1000,
    "rows_skipped_existing": 0,
    "rejection_breakdown": {},
    "reconciled": True,
    "duration_ms": 12,
    "error": None,
  }
  assert list(data)[:3] == ["run_id", "source_file", "status"]


def test_early_failure_reports_null_counts_not_zero(tmp_path):
  path = write_json(failed_early_result(), tmp_path)

  data = json.loads(path.read_text(encoding="utf-8"))
  assert path.name == f"{RUN_ID}.json"
  assert [data[k] for k in ("rows_in", "rows_valid", "rows_rejected", "rows_loaded")] == [None] * 4
  assert data["rows_skipped_existing"] is None
  assert data["reconciled"] is False
  assert data["error"] == "input file not found: data/missing.csv"


def test_json_file_is_created_in_a_missing_directory(tmp_path):
  path = write_json(success_result(), tmp_path / "nested" / "reports")

  assert json.loads(path.read_text(encoding="utf-8"))["status"] == "SUCCESS"


def test_markdown_lists_counts_and_the_breakdown():
  result = RunResult(
    run_id=RUN_ID,
    source_file="data/sales_defective.csv",
    status="SUCCESS_WITH_REJECTS",
    rows_in=1000,
    rows_valid=988,
    rows_rejected=12,
    rows_loaded=988,
    rows_skipped_existing=0,
    rejection_breakdown={"missing_product": 2, "non_positive_unit_price": 3},
    reconciled=True,
    duration_ms=5,
  )

  markdown = to_markdown(result)

  assert f"## Run {RUN_ID}" in markdown
  assert "| Rows rejected | 12 |" in markdown
  assert "| `non_positive_unit_price` | 3 |" in markdown
  assert "| Error |" not in markdown


def test_markdown_shows_unknown_counts_and_the_error():
  markdown = to_markdown(failed_early_result())

  assert "| Rows in | n/a |" in markdown
  assert "| Reconciled | no |" in markdown
  assert "| Error | input file not found: data/missing.csv |" in markdown
