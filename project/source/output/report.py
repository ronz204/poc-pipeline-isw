import json
from dataclasses import asdict
from pathlib import Path

from source.engine.status import RunResult


def write_json(result: RunResult, reports_dir: Path) -> Path:
  reports_dir.mkdir(parents=True, exist_ok=True)
  path = reports_dir / f"{result.run_id}.json"
  path.write_text(json.dumps(asdict(result), indent=2) + "\n", encoding="utf-8")
  return path


def to_markdown(result: RunResult) -> str:
  lines = [
    f"## Run {result.run_id}",
    "",
    "| Field | Value |",
    "|---|---|",
    f"| Source file | `{result.source_file}` |",
    f"| Status | {result.status} |",
    f"| Rows in | {_cell(result.rows_in)} |",
    f"| Rows valid | {_cell(result.rows_valid)} |",
    f"| Rows rejected | {_cell(result.rows_rejected)} |",
    f"| Rows loaded | {_cell(result.rows_loaded)} |",
    f"| Rows skipped (already existing) | {_cell(result.rows_skipped_existing)} |",
    f"| Reconciled | {'yes' if result.reconciled else 'no'} |",
    f"| Duration | {_cell(result.duration_ms)} ms |",
  ]
  if result.error:
    lines.append(f"| Error | {result.error} |")
  if result.rejection_breakdown:
    lines += ["", "### Rejections by reason", "", "| Reason | Rows |", "|---|---|"]
    lines += [f"| `{code}` | {count} |" for code, count in result.rejection_breakdown.items()]
  return "\n".join(lines) + "\n"


def _cell(value: int | None) -> str:
  return "n/a" if value is None else str(value)
