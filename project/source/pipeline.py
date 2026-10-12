import secrets
import tempfile
from collections import Counter
from contextlib import ExitStack, closing
from datetime import UTC, datetime
from decimal import Decimal
from pathlib import Path
from time import perf_counter

import psycopg
import structlog

from source.audit import (
  FAILED,
  SUCCESS,
  SUCCESS_WITH_REJECTS,
  RunError,
  RunResult,
  audited_run,
  failure_message,
)
from source.database import connect, ensure_schema
from source.extract import ExtractError, extract
from source.load import insert_sales
from source.logs import run_logger
from source.quarantine import persist_rejections, write_rejected_csv
from source.reconcile import reconcile
from source.report import Report
from source.settings import Settings
from source.transform import transform
from source.validate import validate


def run_pipeline(source: Path, settings: Settings) -> Report:
  run_id = _new_run_id()
  result = RunResult()
  clock = perf_counter()
  log = None
  with ExitStack() as stack:
    try:
      _require_writable(settings.reports_dir, "reports")
      _require_writable(settings.logs_dir, "logs")
      log = stack.enter_context(run_logger(run_id, settings.logs_dir))
      log.info("run_started", source_file=source.as_posix())
      _execute(source, settings, run_id, result, log)
    except Exception as exc:
      result.status = FAILED
      result.error = failure_message(exc)
    report = Report.from_result(run_id, source.as_posix(), result, round((perf_counter() - clock) * 1000))
    report.write_json(settings.reports_dir)
    if log is not None:
      _log_outcome(log, report)
  return report


def reject_rate_exceeded(rows_rejected: int, rows_in: int, threshold: float) -> bool:
  return Decimal(rows_rejected) > Decimal(str(threshold)) * rows_in


def _execute(
  source: Path, settings: Settings, run_id: str, result: RunResult, log: structlog.stdlib.BoundLogger
) -> None:
  with closing(_connect(settings)) as conn:
    ensure_schema(conn)
    with audited_run(conn, run_id, source.as_posix(), result):
      try:
        extracted = extract(source, settings.max_input_bytes)
      except ExtractError as exc:
        raise RunError(str(exc)) from exc
      log.info("extract_done", rows_in=extracted.rows_in)
      if extracted.extra_columns:
        log.info("extra_columns", columns=list(extracted.extra_columns))

      validation = validate(extracted)
      breakdown = Counter(code for item in validation.rejected for code in item.reasons)
      result.rows_in = extracted.rows_in
      result.rows_valid = len(validation.valid)
      result.rows_rejected = len(validation.rejected)
      result.rows_loaded = 0
      result.rows_skipped_existing = 0
      result.rejection_breakdown = dict(sorted(breakdown.items()))
      log.info("validate_done", rows_valid=result.rows_valid, rows_rejected=result.rows_rejected)

      if validation.rejected:
        persist_rejections(conn, run_id, validation.rejected)
        write_rejected_csv(settings.reports_dir, run_id, validation.rejected)
        log.warning("rows_rejected", rejection_breakdown=result.rejection_breakdown)

      if reject_rate_exceeded(result.rows_rejected, result.rows_in, settings.max_reject_rate):
        raise RunError(
          f"reject rate {result.rows_rejected}/{result.rows_in} is above the threshold "
          f"{settings.max_reject_rate}"
        )

      sales = transform(validation.valid)
      log.info("transform_done", rows=len(sales))
      with conn.transaction():
        counts = insert_sales(conn, run_id, sales)
        log.info("load_done", rows_loaded=counts.loaded, rows_skipped_existing=counts.skipped_existing)
        reconcile(
          conn,
          run_id,
          rows_in=result.rows_in,
          rows_valid=result.rows_valid,
          rows_rejected=result.rows_rejected,
          load=counts,
          transaction_ids=[sale.transaction_id for sale in sales],
        )
      log.info("reconcile_done", reconciled=True)

      result.rows_loaded = counts.loaded
      result.rows_skipped_existing = counts.skipped_existing
      result.reconciled = True
      result.status = SUCCESS_WITH_REJECTS if result.rows_rejected else SUCCESS


def _connect(settings: Settings) -> psycopg.Connection:
  try:
    return connect(settings)
  except psycopg.OperationalError:
    raise RunError("database connection failed") from None


def _require_writable(directory: Path, label: str) -> None:
  try:
    directory.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryFile(dir=directory):
      pass
  except OSError:
    raise RunError(f"{label} directory is not writable: {directory}") from None


def _log_outcome(log: structlog.stdlib.BoundLogger, report: Report) -> None:
  fields = {
    "status": report.status,
    "rows_in": report.rows_in,
    "rows_valid": report.rows_valid,
    "rows_rejected": report.rows_rejected,
    "rows_loaded": report.rows_loaded,
    "rows_skipped_existing": report.rows_skipped_existing,
    "reconciled": report.reconciled,
    "duration_ms": report.duration_ms,
  }
  if report.status == FAILED:
    log.error("run_failed", error=report.error, **fields)
  else:
    log.info("run_finished", **fields)


def _new_run_id() -> str:
  return f"{datetime.now(UTC):%Y%m%dT%H%M%S}-{secrets.token_hex(3)}"
