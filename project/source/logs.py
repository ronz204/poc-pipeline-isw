import logging
import sys
from collections.abc import Generator
from contextlib import contextmanager
from pathlib import Path
from typing import TextIO

import structlog

SHARED_PROCESSORS = [
  structlog.stdlib.add_log_level,
  structlog.processors.TimeStamper(fmt="iso", utc=True),
]


@contextmanager
def run_logger(
  run_id: str, logs_dir: Path, console: TextIO | None = None
) -> Generator[structlog.stdlib.BoundLogger, None, None]:
  logs_dir.mkdir(parents=True, exist_ok=True)
  file_handler = logging.FileHandler(logs_dir / f"{run_id}.jsonl", encoding="utf-8")
  file_handler.setFormatter(_formatter(structlog.processors.JSONRenderer()))
  console_handler = logging.StreamHandler(console or sys.stderr)
  console_handler.setFormatter(_formatter(structlog.dev.ConsoleRenderer(colors=False)))

  backend = logging.getLogger(f"piper.{run_id}")
  backend.setLevel(logging.INFO)
  backend.propagate = False
  backend.handlers = [console_handler, file_handler]
  try:
    yield structlog.wrap_logger(
      backend,
      processors=[*SHARED_PROCESSORS, structlog.stdlib.ProcessorFormatter.wrap_for_formatter],
      wrapper_class=structlog.stdlib.BoundLogger,
    ).bind(run_id=run_id)
  finally:
    backend.handlers = []
    console_handler.close()
    file_handler.close()


def _formatter(renderer: structlog.typing.Processor) -> structlog.stdlib.ProcessorFormatter:
  return structlog.stdlib.ProcessorFormatter(
    processors=[
      structlog.stdlib.ProcessorFormatter.remove_processors_meta,
      renderer,
    ]
  )
