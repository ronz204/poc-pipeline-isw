import pytest

from source.cli import main
from source.generator import CLEAN_FILE, DEFECTIVE_FILE


def test_generate_writes_both_datasets(tmp_path, capsys):
  assert main(["generate", "--output", str(tmp_path / "data")]) == 0

  assert sorted(path.name for path in (tmp_path / "data").iterdir()) == sorted([CLEAN_FILE, DEFECTIVE_FILE])
  assert CLEAN_FILE in capsys.readouterr().out


def test_unknown_command_is_a_usage_error():
  with pytest.raises(SystemExit) as exit_info:
    main(["bogus"])

  assert exit_info.value.code == 2


@pytest.fixture
def isolated(tmp_path, monkeypatch):
  monkeypatch.setenv("REPORTS_DIR", str(tmp_path / "reports"))
  monkeypatch.setenv("LOGS_DIR", str(tmp_path / "logs"))
  return tmp_path


@pytest.mark.integration
def test_run_prints_the_summary_and_exits_zero_on_success(isolated, capsys, conn):
  path = isolated / "tiny.csv"
  path.write_text(
    "transaction_id,product,category,quantity,unit_price,transaction_date,country\n"
    "600000000001,Cli Lamp,home,1,2.00,2025-03-01,peru\n",
    encoding="utf-8",
  )

  try:
    assert main(["run", str(path)]) == 0
    assert "| Status | SUCCESS |" in capsys.readouterr().out
  finally:
    conn.execute("DELETE FROM sales WHERE transaction_id = 600000000001")
    for report in (isolated / "reports").glob("*.json"):
      conn.execute("DELETE FROM etl_runs WHERE run_id = %s", (report.stem,))


@pytest.mark.integration
def test_run_exits_one_when_the_run_fails(isolated, capsys, conn):
  assert main(["run", str(isolated / "absent.csv")]) == 1

  assert "| Status | FAILED |" in capsys.readouterr().out
  for report in (isolated / "reports").glob("*.json"):
    conn.execute("DELETE FROM etl_runs WHERE run_id = %s", (report.stem,))


def test_run_exits_one_with_a_clear_error_when_reports_directory_is_unwritable(tmp_path, monkeypatch, capsys):
  blocker = tmp_path / "blocker"
  blocker.write_text("file", encoding="utf-8")
  monkeypatch.setenv("REPORTS_DIR", str(blocker / "reports"))
  monkeypatch.setenv("LOGS_DIR", str(tmp_path / "logs"))

  assert main(["run", str(tmp_path / "any.csv")]) == 1

  assert "error:" in capsys.readouterr().err
