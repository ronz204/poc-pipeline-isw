import secrets
import tempfile
from collections import Counter
from collections.abc import Sequence
from contextlib import ExitStack, closing
from dataclasses import asdict
from datetime import UTC, datetime
from decimal import Decimal
from pathlib import Path
from time import perf_counter

import pandas as pd
import psycopg
import structlog

from source.config.settings import Settings
from source.engine.audit import audited_run
from source.engine.status import FAILED, SUCCESS, SUCCESS_WITH_REJECTS, RunError, RunResult, failure_message
from source.engine.verify import reconcile
from source.ingest.reader import ExtractError, extract
from source.ingest.rules import Rejection, Validation, validate
from source.ingest.shaper import transform
from source.output.exports import write_rejected_csv
from source.output.logger import run_logger
from source.output.report import write_json
from source.storage.connect import connect, ensure_schema
from source.storage.rejects import persist_rejections
from source.storage.sales import insert_sales

Logger = structlog.stdlib.BoundLogger
LOG_EXCLUDED = ("run_id", "source_file", "rejection_breakdown", "error")


def run_pipeline(source: Path, settings: Settings) -> RunResult:
  result = RunResult(run_id=_new_run_id(), source_file=source.as_posix())
  clock = perf_counter()
  log = None
  with ExitStack() as stack:
    try:
      _require_writable(settings.reports_dir, "reports")
      _require_writable(settings.logs_dir, "logs")
      log = stack.enter_context(run_logger(result.run_id, settings.logs_dir))
      log.info("run_started", source_file=result.source_file)
      _execute(source, settings, result, log)
    except Exception as exc:
      result.status = FAILED
      result.error = failure_message(exc)
    if result.duration_ms is None:
      result.duration_ms = round((perf_counter() - clock) * 1000)
    write_json(result, settings.reports_dir)
    if log is not None:
      _log_outcome(log, result)
  return result


def reject_rate_exceeded(rows_rejected: int, rows_in: int, threshold: float) -> bool:
  return Decimal(rows_rejected) > Decimal(str(threshold)) * rows_in


def _execute(source: Path, settings: Settings, result: RunResult, log: Logger) -> None:
  with closing(_connect(settings)) as conn:
    ensure_schema(conn)
    with audited_run(conn, result):
      validation = _read(source, settings, result, log)
      _quarantine(conn, settings, result, validation.rejected, log)
      _enforce_threshold(settings, result)
      _load(conn, result, validation.valid, log)


def _read(source: Path, settings: Settings, result: RunResult, log: Logger) -> Validation:
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
  return validation


def _quarantine(
  conn: psycopg.Connection, settings: Settings, result: RunResult, rejected: Sequence[Rejection], log: Logger
) -> None:
  if not rejected:
    return
  persist_rejections(conn, result.run_id, rejected)
  write_rejected_csv(settings.reports_dir, result.run_id, rejected)
  log.warning("rows_rejected", rejection_breakdown=result.rejection_breakdown)


def _enforce_threshold(settings: Settings, result: RunResult) -> None:
  if reject_rate_exceeded(result.rows_rejected, result.rows_in, settings.max_reject_rate):
    raise RunError(
      f"reject rate {result.rows_rejected}/{result.rows_in} is above the threshold {settings.max_reject_rate}"
    )


def _load(conn: psycopg.Connection, result: RunResult, valid: pd.DataFrame, log: Logger) -> None:
  sales = transform(valid)
  log.info("transform_done", rows=len(sales))
  with conn.transaction():
    counts = insert_sales(conn, result.run_id, sales)
    log.info("load_done", rows_loaded=counts.loaded, rows_skipped_existing=counts.skipped_existing)
    reconcile(
      conn,
      result.run_id,
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


def _log_outcome(log: Logger, result: RunResult) -> None:
  fields = {key: value for key, value in asdict(result).items() if key not in LOG_EXCLUDED}
  if result.status == FAILED:
    log.error("run_failed", error=result.error, **fields)
  else:
    log.info("run_finished", **fields)


def _new_run_id() -> str:
  return f"{datetime.now(UTC):%Y%m%dT%H%M%S}-{secrets.token_hex(3)}"
