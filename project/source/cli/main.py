import argparse
import sys
from collections.abc import Sequence
from pathlib import Path

from source.config.settings import ConfigError, load_settings
from source.engine.runner import run_pipeline
from source.engine.status import FAILED
from source.tools.dataset import generate_datasets

DEFAULT_DATA_DIR = Path("data")


def main(argv: Sequence[str] | None = None) -> int:
  args = _parser().parse_args(argv)
  try:
    return args.handler(args)
  except (ConfigError, OSError) as exc:
    print(f"error: {exc}", file=sys.stderr)
    return 1


def _parser() -> argparse.ArgumentParser:
  parser = argparse.ArgumentParser(prog="piper", description="Sales CSV ETL pipeline")
  commands = parser.add_subparsers(dest="command", required=True)

  run = commands.add_parser("run", help="validate, quarantine, and load a sales CSV")
  run.add_argument("csv", type=Path, help="path of the sales CSV")
  run.set_defaults(handler=_run)

  generate = commands.add_parser("generate", help="write the deterministic synthetic datasets")
  generate.add_argument("--output", type=Path, default=DEFAULT_DATA_DIR, help="directory for the CSV files")
  generate.set_defaults(handler=_generate)
  return parser


def _run(args: argparse.Namespace) -> int:
  report = run_pipeline(args.csv, load_settings())
  print(report.to_markdown())
  return 1 if report.status == FAILED else 0


def _generate(args: argparse.Namespace) -> int:
  for path in generate_datasets(args.output):
    print(path)
  return 0
