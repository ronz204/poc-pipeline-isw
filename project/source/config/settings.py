import os
from collections.abc import Callable, Mapping
from dataclasses import dataclass, field
from pathlib import Path

DEFAULT_DB_HOST = "127.0.0.1"
DEFAULT_DB_PORT = 5432
DEFAULT_REPORTS_DIR = "reports"
DEFAULT_LOGS_DIR = "logs"
DEFAULT_MAX_REJECT_RATE = 0.2
DEFAULT_MAX_INPUT_MB = 50.0
BYTES_PER_MB = 1024 * 1024


class ConfigError(ValueError):
  pass


@dataclass(frozen=True)
class Settings:
  db_host: str
  db_port: int
  db_user: str
  db_password: str = field(repr=False)
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


def load_settings(env: Mapping[str, str] | None = None) -> Settings:
  env = os.environ if env is None else env
  return Settings(
    db_host=env.get("POSTGRES_HOST") or DEFAULT_DB_HOST,
    db_port=_number(env, "POSTGRES_PORT", int, DEFAULT_DB_PORT),
    db_user=_required(env, "POSTGRES_USER"),
    db_password=_required(env, "POSTGRES_PASSWORD"),
    db_name=_required(env, "POSTGRES_DB"),
    reports_dir=Path(env.get("REPORTS_DIR") or DEFAULT_REPORTS_DIR),
    logs_dir=Path(env.get("LOGS_DIR") or DEFAULT_LOGS_DIR),
    max_reject_rate=_load_max_reject_rate(env),
    max_input_bytes=_load_max_input_bytes(env),
  )


def _load_max_reject_rate(env: Mapping[str, str]) -> float:
  rate = _number(env, "MAX_REJECT_RATE", float, DEFAULT_MAX_REJECT_RATE)
  if not 0 <= rate <= 1:
    raise ConfigError("MAX_REJECT_RATE must be between 0 and 1")
  return rate


def _load_max_input_bytes(env: Mapping[str, str]) -> int:
  megabytes = _number(env, "MAX_INPUT_MB", float, DEFAULT_MAX_INPUT_MB)
  if megabytes <= 0:
    raise ConfigError("MAX_INPUT_MB must be greater than 0")
  return int(megabytes * BYTES_PER_MB)


def _required(env: Mapping[str, str], name: str) -> str:
  if not (value := env.get(name)):
    raise ConfigError(f"missing required environment variable {name}")
  return value


def _number[T](env: Mapping[str, str], name: str, kind: Callable[[str], T], default: T) -> T:
  if not (raw := env.get(name)):
    return default
  try:
    return kind(raw)
  except ValueError:
    raise ConfigError(f"{name} must be a number") from None
