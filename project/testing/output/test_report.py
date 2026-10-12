import json

from source.engine.audit import FAILED, SUCCESS, RunResult
from source.output.report import Report

RUN_ID = "20250101T120000-a1b2c3"


def success_report():
  result = RunResult(
    status=SUCCESS,
    rows_in=1000,
    rows_valid=1000,
    rows_rejected=0,
    rows_loaded=1000,
    rows_skipped_existing=0,
    reconciled=True,
  )
  return Report.from_result(RUN_ID, "data/sales_valid.csv", result, 12)


def failed_early_report():
  result = RunResult(status=FAILED, error="input file not found: data/missing.csv")
  return Report.from_result(RUN_ID, "data/missing.csv", result, 3)


def test_report_has_the_documented_shape():
  assert success_report().to_dict() == {
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


def test_early_failure_reports_null_counts_not_zero(tmp_path):
  path = failed_early_report().write_json(tmp_path)

  data = json.loads(path.read_text(encoding="utf-8"))
  assert path.name == f"{RUN_ID}.json"
  assert [data[k] for k in ("rows_in", "rows_valid", "rows_rejected", "rows_loaded")] == [None] * 4
  assert data["rows_skipped_existing"] is None
  assert data["reconciled"] is False
  assert data["error"] == "input file not found: data/missing.csv"


def test_json_file_is_created_in_a_missing_directory(tmp_path):
  path = success_report().write_json(tmp_path / "nested" / "reports")

  assert json.loads(path.read_text(encoding="utf-8"))["status"] == "SUCCESS"


def test_markdown_lists_counts_and_the_breakdown():
  result = RunResult(
    status="SUCCESS_WITH_REJECTS",
    rows_in=1000,
    rows_valid=988,
    rows_rejected=12,
    rows_loaded=988,
    rows_skipped_existing=0,
    rejection_breakdown={"missing_product": 2, "non_positive_unit_price": 3},
    reconciled=True,
  )

  markdown = Report.from_result(RUN_ID, "data/sales_defective.csv", result, 5).to_markdown()

  assert f"## Run {RUN_ID}" in markdown
  assert "| Rows rejected | 12 |" in markdown
  assert "| `non_positive_unit_price` | 3 |" in markdown
  assert "| Error |" not in markdown


def test_markdown_shows_unknown_counts_and_the_error():
  markdown = failed_early_report().to_markdown()

  assert "| Rows in | n/a |" in markdown
  assert "| Reconciled | no |" in markdown
  assert "| Error | input file not found: data/missing.csv |" in markdown
