import json
from dataclasses import asdict, dataclass
from pathlib import Path

from source.engine.status import RunResult


@dataclass(frozen=True)
class Report:
  run_id: str
  source_file: str
  status: str
  rows_in: int | None
  rows_valid: int | None
  rows_rejected: int | None
  rows_loaded: int | None
  rows_skipped_existing: int | None
  rejection_breakdown: dict[str, int]
  reconciled: bool
  duration_ms: int
  error: str | None

  @classmethod
  def from_result(cls, run_id: str, source_file: str, result: RunResult, duration_ms: int) -> "Report":
    return cls(
      run_id=run_id,
      source_file=source_file,
      status=result.status,
      rows_in=result.rows_in,
      rows_valid=result.rows_valid,
      rows_rejected=result.rows_rejected,
      rows_loaded=result.rows_loaded,
      rows_skipped_existing=result.rows_skipped_existing,
      rejection_breakdown=dict(result.rejection_breakdown),
      reconciled=result.reconciled,
      duration_ms=duration_ms,
      error=result.error,
    )

  def to_dict(self) -> dict:
    return asdict(self)

  def write_json(self, reports_dir: Path) -> Path:
    reports_dir.mkdir(parents=True, exist_ok=True)
    path = reports_dir / f"{self.run_id}.json"
    path.write_text(json.dumps(self.to_dict(), indent=2) + "\n", encoding="utf-8")
    return path

  def to_markdown(self) -> str:
    lines = [
      f"## Run {self.run_id}",
      "",
      "| Field | Value |",
      "|---|---|",
      f"| Source file | `{self.source_file}` |",
      f"| Status | {self.status} |",
      f"| Rows in | {_cell(self.rows_in)} |",
      f"| Rows valid | {_cell(self.rows_valid)} |",
      f"| Rows rejected | {_cell(self.rows_rejected)} |",
      f"| Rows loaded | {_cell(self.rows_loaded)} |",
      f"| Rows skipped (already existing) | {_cell(self.rows_skipped_existing)} |",
      f"| Reconciled | {'yes' if self.reconciled else 'no'} |",
      f"| Duration | {self.duration_ms} ms |",
    ]
    if self.error:
      lines.append(f"| Error | {self.error} |")
    if self.rejection_breakdown:
      lines += ["", "### Rejections by reason", "", "| Reason | Rows |", "|---|---|"]
      lines += [f"| `{code}` | {count} |" for code, count in self.rejection_breakdown.items()]
    return "\n".join(lines) + "\n"


def _cell(value: int | None) -> str:
  return "n/a" if value is None else str(value)
