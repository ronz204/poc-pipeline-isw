from dataclasses import dataclass, field

RUNNING = "RUNNING"
SUCCESS = "SUCCESS"
SUCCESS_WITH_REJECTS = "SUCCESS_WITH_REJECTS"
FAILED = "FAILED"


class RunError(Exception):
  pass


def failure_message(exc: BaseException) -> str:
  return str(exc) if isinstance(exc, RunError) else type(exc).__name__


@dataclass
class RunResult:
  run_id: str
  source_file: str
  status: str = RUNNING
  rows_in: int | None = None
  rows_valid: int | None = None
  rows_rejected: int | None = None
  rows_loaded: int | None = None
  rows_skipped_existing: int | None = None
  rejection_breakdown: dict[str, int] = field(default_factory=dict)
  reconciled: bool = False
  duration_ms: int | None = None
  error: str | None = None
