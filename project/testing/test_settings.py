from pathlib import Path

import pytest

from source.settings import SettingsError, load_settings

CREDENTIALS = {"POSTGRES_USER": "u", "POSTGRES_PASSWORD": "p", "POSTGRES_DB": "d"}


def test_defaults_apply_when_only_credentials_are_set():
  settings = load_settings(CREDENTIALS)

  assert settings.db_host == "127.0.0.1"
  assert settings.db_port == 5432
  assert settings.reports_dir == Path("reports")
  assert settings.logs_dir == Path("logs")
  assert settings.max_reject_rate == 0.2
  assert settings.max_input_bytes == 50 * 1024 * 1024


def test_overrides_are_read_from_the_environment():
  env = CREDENTIALS | {
    "POSTGRES_HOST": "database",
    "POSTGRES_PORT": "5433",
    "REPORTS_DIR": "/out/reports",
    "MAX_REJECT_RATE": "0.005",
    "MAX_INPUT_MB": "1",
  }

  settings = load_settings(env)

  assert settings.connection_params() == {
    "host": "database",
    "port": 5433,
    "user": "u",
    "password": "p",
    "dbname": "d",
  }
  assert settings.reports_dir == Path("/out/reports")
  assert settings.max_reject_rate == 0.005
  assert settings.max_input_bytes == 1024 * 1024


@pytest.mark.parametrize("missing", sorted(CREDENTIALS))
def test_missing_credential_is_an_error_naming_the_variable(missing):
  env = {k: v for k, v in CREDENTIALS.items() if k != missing}

  with pytest.raises(SettingsError, match=missing):
    load_settings(env)


@pytest.mark.parametrize(
  ("name", "value"),
  [
    ("POSTGRES_PORT", "abc"),
    ("MAX_REJECT_RATE", "x"),
    ("MAX_REJECT_RATE", "1.5"),
    ("MAX_INPUT_MB", "0"),
  ],
)
def test_invalid_numbers_are_rejected(name, value):
  with pytest.raises(SettingsError, match=name):
    load_settings(CREDENTIALS | {name: value})
