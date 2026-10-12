# Piper

An ETL pipeline that reads sales CSVs, validates every row against declared quality rules, quarantines invalid rows with their reasons, and loads the valid ones idempotently into PostgreSQL. Each run is audited and reconciled against database state, so no row is lost or loaded silently. Python 3.12, uv, pandas, PostgreSQL 17, Docker Compose, GitHub Actions.

---

## Knowledge base layout

| Path | Holds |
|---|---|
| `.claude/docs/` | Self-contained reference files, one concern each: vision and domain vocabulary, component behavior, stack and topology, data model, mechanism explanations, build approach, and the delta methodology culture |
| `.claude/rules/` | Conventions auto-loaded when a matching file is opened or edited, scoped by `paths:` frontmatter |
| `.claude/skills/` | The delta pipeline: `surveyor` (bootstrap), `specifier` (interview), `archivist` (write), `sentinel` (verify) |
| `.claude/settings.json` | Permission policy, see Permissions below |
| `project/deltas/` | Per-slice contracts: `<slice>.spec.md`, optional `<slice>.design.md` |

## Repo layout

| Path | Purpose |
|---|---|
| `project/` | The whole application; every tool command runs from here |
| `project/source/` | The importable package (`source`); no `__init__.py` files |
| `project/testing/` | Tests |
| `project/data/` | Synthetic input CSVs |
| `project/docker/` | One subfolder per Compose service; currently the database service |
| `project/compose.yml` | Root Compose file; includes the database service and defines the pipeline service |
| `project/Dockerfile` | Image of the pipeline service |
| `project/pyproject.toml` | Project metadata, dependencies, installed command |
| `.github/workflows/` | CI, which runs inside `project/` |
| `README.md` | Entry point for people cloning the repository |

## Setup & common commands

Run from `project/`.

| Task | Command |
|---|---|
| Install dependencies | `uv sync` |
| Start the database | `docker compose up -d` |
| Stop and reset the database | `docker compose down -v` |

Test, lint, and pipeline-run commands are not defined yet; they arrive with the first dependencies and source code.

## Permissions

The full policy lives in `.claude/settings.json`. Reading env and secret files and pushing or pulling with git are denied; read-only git commands, Docker Compose, `docker exec`, `curl`, and web search are pre-approved.

## Conventions

Always-on conventions live in `.claude/rules/`. Project-wide non-negotiables:

- Every row is accounted for: valid and loaded, or rejected and recorded. Nothing is dropped or loaded silently.
- Source code, identifiers, and runtime messages are in English.

---

## Non-goals

- Not a production data platform: no scheduler, deployment pipeline, or alerting.
