import os
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path

BYTES_PER_MB = 1024 * 1024


class SettingsError(ValueError):
  pass


@dataclass(frozen=True)
class Settings:
  db_host: str
  db_port: int
  db_user: str
  db_password: str
  db_name: str
  reports_dir: Path
  logs_dir: Path
  max_reject_rate: float
  max_input_bytes: int

  def connection_params(self) -> dict[str, str | int]:
    return {
      "host": self.db_host,
      "port": self.db_port,
      "user": self.db_user,
      "password": self.db_password,
      "dbname": self.db_name,
    }


def _required(env: Mapping[str, str], name: str) -> str:
  if not (value := env.get(name)):
    raise SettingsError(f"missing required environment variable {name}")
  return value


def _number[T: (int, float)](env: Mapping[str, str], name: str, default: T) -> T:
  try:
    return type(default)(env.get(name) or default)
  except ValueError:
    raise SettingsError(f"{name} must be a number") from None


def load_settings(env: Mapping[str, str] | None = None) -> Settings:
  env = os.environ if env is None else env
  max_reject_rate = _number(env, "MAX_REJECT_RATE", 0.2)
  max_input_mb = _number(env, "MAX_INPUT_MB", 50.0)
  if not 0 <= max_reject_rate <= 1:
    raise SettingsError("MAX_REJECT_RATE must be between 0 and 1")
  if max_input_mb <= 0:
    raise SettingsError("MAX_INPUT_MB must be greater than 0")
  return Settings(
    db_host=env.get("POSTGRES_HOST") or "127.0.0.1",
    db_port=_number(env, "POSTGRES_PORT", 5432),
    db_user=_required(env, "POSTGRES_USER"),
    db_password=_required(env, "POSTGRES_PASSWORD"),
    db_name=_required(env, "POSTGRES_DB"),
    reports_dir=Path(env.get("REPORTS_DIR") or "reports"),
    logs_dir=Path(env.get("LOGS_DIR") or "logs"),
    max_reject_rate=max_reject_rate,
    max_input_bytes=int(max_input_mb * BYTES_PER_MB),
  )
