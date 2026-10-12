# Approach

The order and philosophy behind building the pipeline and its delivery practices. Why the system exists and its scope boundaries live elsewhere.

---

## Technical pillars

| Pillar | What it means here |
|---|---|
| Reproducible environment | Container runtime, pinned dependencies (lockfile), and a locked install everywhere. The same commands work on a developer machine, in the image, and in CI. |
| Data quality inside the pipeline | Rules are declared, enforced before load, mirrored by database constraints, and every rejection is kept with its reason. Without this the audit trail would only record failures, not prevent them. |
| Accountability of every row | Counts are reconciled against database state and each run is audited. Tests and CI exist to keep this guarantee from regressing. |

They are built together because the point is not any one of them: a reproducible run is only meaningful if its outcome can be verified, and verification is only trustworthy if the environment is the same everywhere.

## Functional scope

- Load a CSV of sales into PostgreSQL after validation, normalization, and exact total computation.
- Reject invalid rows into quarantine with all their reason codes; never load them and never drop them silently.
- Fail a run, loading nothing, when the reject rate exceeds the threshold.
- Make re-running the same file safe.
- Record every run in an audit table and emit per-run evidence (JSON report, rejected CSV, structured log, Markdown summary).
- Generate deterministic clean and defective datasets with known expected outcomes.
- Run the database and pipeline in containers, and run lint, tests, and an end-to-end pipeline run in CI.

## Roadmap

1. **Knowledge base and project skeleton** — project layout, Compose layout, and decisions captured; the first slice (the pipeline run) not yet specified. Done when the docs and skeleton exist.
2. **Specify the pipeline run slice** — contract, invariants, and open questions for validate, quarantine, load, reconcile, and audit, before implementation.
3. **Dependencies, schema, and configuration** — declare dependencies, database schema, and settings loading; the database service starts healthy.
4. **Validation and transformation** — declared rules with named checks, normalization, and the synthetic datasets, with the unit and property tests that pin the expected rejections.
5. **Load, reconciliation, and orchestration** — quarantine, idempotent load, real reconciliation, run audit, reports, and logging; integration tests against a real database.
6. **Containers and CI** — image, Compose services, workflow with a mandatory database in tests and an end-to-end run.
7. **Evidence and delivery** — run the demo end to end, record real counts, and document limitations and manual steps honestly.

## Risks

- Several pieces are unverified until executed: the image build, the Compose run path, the CI workflow.
- Translating the validation library's failure reports into per-row reason codes may prove more awkward than plain pandas masks; the fallback is to drop the library.
- pandas 3 changed text dtype and copy behavior; the suite must run on the locked version from the first day.
- A non-root container user may lack write permission on mounted output directories on some hosts.

## Done criteria

- The valid dataset loads 1000 of 1000 rows with `SUCCESS` and reconciliation passing; the defective dataset yields 988 valid, 12 rejected with the documented breakdown, `SUCCESS_WITH_REJECTS`, and 1988 sales in total.
- Running the valid file twice loads nothing the second time (all rows skipped) and leaves the row count unchanged.
- Lowering the reject threshold below the defective dataset's rate makes the run end `FAILED` with nothing loaded and the rejects still recorded.
- The full test suite passes locally and in CI, with a missing database failing the integration tests instead of skipping them.
- Breaking a validation rule on purpose makes tests fail.
- A fresh clone follows the documented commands from scratch to a working run.

## Stretch goals

- Coverage reporting in CI.
- Pre-commit hooks running the same lint as CI.
- A bulk-copy load path for larger volumes.

---

## Non-goals

- Production deployment, scheduling, or monitoring are not part of the sequence.
