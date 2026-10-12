# Overview

What the system is for, its scope, and the vocabulary the rest of the knowledge base assumes. How the parts are built and wired is not covered here.

---

## Vision

A small ETL pipeline that loads sales records from CSV files into PostgreSQL and demonstrates DataOps practices around it: reproducible environments, automated tests, continuous integration, a per-run audit trail, and data quality enforced as part of the process rather than after the fact.

The central guarantee is that no row is lost or loaded silently. Every input row ends up in exactly one place: the destination table, or quarantine with the reasons it was rejected. A run that cannot account for its rows fails instead of reporting success.

## Scope & non-goals

The system owns:

- Reading a CSV file as raw text, validating every row against declared quality rules, normalizing the valid rows, and loading them into PostgreSQL idempotently.
- Isolating invalid rows with their rejection reasons, and aborting the run when too large a share of the input is rejected.
- Auditing each run (counts, status, duration, error) in the database and producing per-run evidence files.
- Generating deterministic synthetic datasets, one clean and one with planted defects, so expected outcomes are known in advance.
- A containerized runtime, automated tests, and a CI workflow that exercises the pipeline end to end.

Non-goals:

- Not a production data platform: no orchestrator or scheduler (each run is launched by hand), no continuous deployment, no image publishing, no alerting or dashboards.
- Not built for volume: the dataset is small and synthetic, and the load path is row by row on purpose.
- No configurable rule catalog or statistical profiling (outlier or per-product range checks); rules are fixed in code.
- No automatic date-format guessing: only ISO dates are accepted.
- No content-level idempotency: a row whose identifier already exists is skipped without comparing its values.

## Domain concepts

| Concept | Description |
|---|---|
| Source file | A CSV of sales transactions with seven required columns: identifier, product, category, quantity, unit price, date, country. Read entirely as text so nothing is coerced before validation. |
| Run | One execution of the pipeline over one source file. It has a unique run identifier that ties together its log events, report, audit row, loaded sales, and rejected records. |
| Sale | A validated, normalized transaction persisted in the destination table, tagged with the run that loaded it. |
| Rejected record | A source row that failed one or more rules. It is kept with its record number, the list of reason codes, and the original raw values, and is never loaded as a sale. |
| Reason code | The stable name of a violated rule (missing field, invalid or non-positive value, out of range, duplicate identifier, wrong column count). One row can carry several. |
| Quarantine | The isolation of rejected records, in the database and in a per-run CSV, so they can be reviewed and reprocessed instead of dropped. |
| Reject-rate threshold | The maximum share of rejected rows a run tolerates. Above it, the source is assumed broken and the run fails without loading anything. |
| Reconciliation | The check that the counts a run reports match what actually exists in the database. A mismatch rolls the load back and fails the run. |
| Run status | `RUNNING` while in flight, then `SUCCESS`, `SUCCESS_WITH_REJECTS`, or `FAILED`. A run is recorded as `RUNNING` first so a crash leaves a trace. |
| Synthetic dataset | The deterministic clean and defective CSV pairs used for demos and tests; the defective one yields a known set of rejections. |
