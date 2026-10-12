# Structure

Stack, runtime topology, infrastructure, and cross-cutting patterns. The data model lives in the persistence reference, not here.

---

## Stack

| Layer | Choice | Rationale |
|---|---|---|
| Language / packaging | Python 3.12 managed with uv (`pyproject.toml` + `uv.lock`) | The lockfile pins exact versions; a locked sync fails when it is stale. No exported requirements file is maintained. |
| Build backend | `uv_build`, configured for a namespace package named `source` with the module root at the project root | Allows packages with no `__init__.py` files. The importable package is `source`; the installed command is `piper`. |
| CSV reading | Python standard CSV reader, every cell kept as text | Text-only reading prevents silent coercion before validation, and rows with a wrong column count can be isolated instead of aborting the run. |
| Tabular container | pandas 3.x (below 4) | Holds the table of text rows that validation runs over; it does not parse the file or judge values. Money never goes through a pandas numeric conversion. |
| Data quality | pandera | Rules are a declared schema of named checks, each a plain predicate over one text value; the check name is the rejection code and lazy validation reports every failure at once. |
| Logging | structlog | Binds the run identifier once; JSON Lines plus a readable console renderer without a custom logging class. |
| Database driver | psycopg 3 (binary) | Parameterized queries, explicit transactions, per-statement affected-row counts. |
| Database | PostgreSQL 17 (alpine image) | Constraints, `ON CONFLICT`, JSONB, array columns, and transactional loads. |
| Tests | pytest, hypothesis | Unit and integration tests, plus a property test of the no-row-lost invariant. |
| Lint | ruff | Single tool for lint and import order. |
| Containers | Docker Compose | Reproducible database and on-demand pipeline container. |
| CI | GitHub Actions | Lint, tests against a service-container database, and an end-to-end run. |

## Topology

```
 CSV (data/) ──► etl container (on demand) ──► database container (PostgreSQL 17)
                  extract ► validate ─┬► transform ► load ► reconcile
                                      └► quarantine
                  │                                    │
                  ▼                                    ▼
        reports/ (JSON, rejected CSV)       tables: etl_runs, sales, rejected_records
        logs/ (JSON Lines)
        stdout: Markdown summary
```

A run is one synchronous process. The pipeline container connects to the database over the internal Compose network; the database is also published on the loopback interface only, so local tooling and tests can reach it.

Order of a run: ensure schema, record the run as `RUNNING`, extract, validate, quarantine rejects, check the reject-rate threshold, transform, load and reconcile in one transaction, set the final status, update the audit row, write reports.

## Infrastructure

- **Compose layout:** a root Compose file named `piper` includes the database service's own Compose file and defines the pipeline service. The database service lives in its own folder under `docker/`, one subfolder per service.
- **Pipeline image:** built from the project's root `Dockerfile`; dependencies are installed in a cached layer before the source is copied; runs as a non-root user; the entrypoint is the installed command. The uv image version is pinned.
- **Pipeline service:** belongs to the `etl` Compose profile, so `up` starts only the database and the pipeline is launched on demand with `run`. It waits for the database healthcheck.
- **Environment files:** each has a committed `.sample` and a git-ignored real file. Database credentials live in the database service's own env file, read by both the database and the pipeline service; application settings (published port, reject-rate threshold, maximum input size) live in the project-level env file.
- **Volumes:** the data directory is mounted into the pipeline container; reports and logs are mounted out; the database uses a named volume.
- **CI:** a workflow at the repository root runs inside the project directory. It starts a PostgreSQL service container with a healthcheck, installs with a locked sync, lints, runs tests with the database mandatory, runs the pipeline end to end on both datasets appending the Markdown summary to the job summary, and uploads reports and logs as an artifact even on failure.
- **Image hygiene:** a `.dockerignore` keeps env files, version-control data, tests, deltas, and outputs out of the build context.

## Cross-cutting patterns

- **Quarantine, never drop:** invalid rows are persisted with reasons, so a failed or partial run still leaves reviewable evidence.
- **Fail loud, account for every row:** reconciliation compares reported counts with database state inside the load transaction; a mismatch is a failure, not a warning.
- **Circuit breaker:** a reject rate above the threshold fails the run before anything is loaded.
- **Idempotent load:** keyed on the transaction identifier. Re-running a file inserts nothing new and counts existing rows as skipped.
- **Defense in depth on data:** every validation rule has a matching database `CHECK`, so a bug in the application cannot persist an out-of-range value.
- **Input is untrusted:** file size is capped; values are range-bound to the column types so an absurd value becomes a rejection instead of a failed insert that would abort the whole batch; report file names are derived only from the generated run identifier.
- **SQL:** statements are parameterized; no data from the CSV is ever concatenated into SQL.
- **Secrets:** only in git-ignored env files; samples carry demo values; Compose refuses to start when database credentials are missing; env files are excluded from the image. CI credentials are throwaway values for an ephemeral service container.
- **Dependencies:** versions are pinned by the lockfile and installed with a locked sync everywhere (local, image, CI).
- **Sensitive data in logs:** logs and reports carry counts and codes only; raw values exist only in the rejected-records table and the quarantine CSV.
- **Output safety:** the quarantine CSV neutralizes spreadsheet formulas.
- **Time:** all timestamps are UTC.

Baseline considerations that do not apply: authentication and authorization (local command-line tool with no network surface of its own), caching, pagination, rate limiting, and background queues. The process keeps no state between runs, so any run can be killed and relaunched; the only persistent state is the database.

## Open architecture decisions

- **Validation mapping:** whether translating pandera failures into per-row reason codes stays simpler than equivalent vectorized masks. If it does not, the rules move to plain pandas masks and the dependency is dropped.

---

## Non-goals

- No deployment target, image registry, or orchestrator is defined; the container exists to make runs reproducible, not to be shipped.
