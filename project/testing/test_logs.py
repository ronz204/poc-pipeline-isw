import io
import json

from source.logs import run_logger

RUN_ID = "20250101T120000-a1b2c3"


def test_every_event_carries_the_run_id_in_console_and_file(tmp_path):
  console = io.StringIO()

  with run_logger(RUN_ID, tmp_path, console) as log:
    log.info("run_started", source_file="data/sales_valid.csv")
    log.info("validate_done", rows_valid=988, rows_rejected=12)

  events = [json.loads(line) for line in (tmp_path / f"{RUN_ID}.jsonl").read_text().splitlines()]
  assert [e["event"] for e in events] == ["run_started", "validate_done"]
  assert all(e["run_id"] == RUN_ID for e in events)
  assert events[1]["rows_rejected"] == 12
  assert all(e["level"] == "info" and e["timestamp"].endswith("Z") for e in events)
  assert console.getvalue().count(RUN_ID) == 2


def test_logs_directory_is_created_and_each_run_gets_its_own_file(tmp_path):
  logs_dir = tmp_path / "nested" / "logs"

  with run_logger("run-a", logs_dir, io.StringIO()) as log:
    log.info("run_started")
  with run_logger("run-b", logs_dir, io.StringIO()) as log:
    log.info("run_started")

  assert sorted(p.name for p in logs_dir.iterdir()) == ["run-a.jsonl", "run-b.jsonl"]


def test_loggers_of_different_runs_do_not_share_output(tmp_path):
  with run_logger("run-a", tmp_path, io.StringIO()) as first:
    first.info("run_started")
    with run_logger("run-b", tmp_path, io.StringIO()) as second:
      second.info("run_started")
    first.info("run_finished")

  lines = (tmp_path / "run-a.jsonl").read_text().splitlines()
  assert [json.loads(line)["event"] for line in lines] == ["run_started", "run_finished"]
  assert len((tmp_path / "run-b.jsonl").read_text().splitlines()) == 1
