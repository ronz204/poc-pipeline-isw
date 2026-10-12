# Roadmap

Linear build progress of the Piper ETL pipeline, from project skeleton to delivered evidence. It tracks what has been built, not a changelog or a decision log.

---

## Overview

**Overall progress: 31 / 39 tasks — 79%**

| # | Step | Status | Progress |
|---|---|---|---|
| 1 | [Knowledge base and project skeleton](#1--knowledge-base-and-project-skeleton) | ✅ Done | 4/4 — 100% |
| 2 | [Specify the pipeline run slice](#2--specify-the-pipeline-run-slice) | ✅ Done | 3/3 — 100% |
| 3 | [Dependencies, schema, and configuration](#3--dependencies-schema-and-configuration) | ✅ Done | 5/5 — 100% |
| 4 | [Validation and transformation](#4--validation-and-transformation) | ✅ Done | 8/8 — 100% |
| 5 | [Load, reconciliation, and orchestration](#5--load-reconciliation-and-orchestration) | ✅ Done | 8/8 — 100% |
| 6 | [Containers and CI](#6--containers-and-ci) | 🔄 In progress | 3/5 — 60% |
| 7 | [Evidence and delivery](#7--evidence-and-delivery) | 🔲 Not started | 0/6 — 0% |

Status legend: 🔲 Not started · 🔄 In progress · ✅ Done (only once every task under it is checked).

---

## 1 — Knowledge base and project skeleton

Requirements and decisions captured, knowledge base bootstrapped, and the project files ready to build on.

- [x] Capture requirements, design decisions, and the security baseline
- [x] Bootstrap `CLAUDE.md`, the reference docs, and the convention rules
- [x] Rename the uv defaults in `pyproject.toml` (project name, command, build backend, tool settings)
- [x] Fill the ignore files and git attributes

## 2 — Specify the pipeline run slice

One contract for the whole run: validate, quarantine, load, reconcile, audit.

- [x] Interview and write the `sales-csv-etl-run` spec (intent, scope, invariants)
- [x] Record the open questions and deferred decisions in the spec
- [x] Check the spec against the reference docs and resolve any conflict

## 3 — Dependencies, schema, and configuration

- [x] Add runtime and dev dependencies with uv and commit `uv.lock`
- [x] Write both env sample files and the database Compose service with its healthcheck
- [x] Write the SQL schema and the schema bootstrap
- [x] Implement settings loading from environment variables
- [x] Confirm the database starts healthy and the schema applies twice without error

## 4 — Validation and transformation

- [x] Extract: text-only CSV reading (byte-order mark, blank lines, size cap, missing columns)
- [x] Validation rules as named checks covering every reason code
- [x] Duplicate detection: first occurrence wins, identifier normalized without leading zeros
- [x] Transformation with exact decimal arithmetic and whitespace-only title casing
- [x] Deterministic dataset generator: clean file and defective file with planted defects
- [x] Unit tests: one per rule and per boundary case
- [x] Property test: valid plus rejected equals input for any input
- [x] Confirm the defective dataset yields exactly 12 rejections and 988 valid rows

## 5 — Load, reconciliation, and orchestration

- [x] Structured logging with the run identifier bound once
- [x] Run audit: `RUNNING` row first, final update in every case
- [x] Quarantine persistence and the rejected CSV with formula neutralization
- [x] Idempotent load with per-row affected counts
- [x] Reconciliation against database state, rolling back on mismatch
- [x] Reject-rate threshold failing the run before anything is loaded
- [x] Run report (JSON and Markdown summary) and the command line with exit code
- [x] Integration tests on real PostgreSQL: valid, invalid, idempotent, threshold, missing column, missing file, database down

## 6 — Containers and CI

- [x] `Dockerfile`: pinned uv, non-root user, cached dependency layer
- [x] Root Compose file with the `etl` profile and env files
- [x] Build the image and run both datasets through Compose
- [ ] CI workflow: lint, tests with a required database, end-to-end run, job summary, artifact upload
- [ ] Green workflow run on GitHub

## 7 — Evidence and delivery

- [ ] Write the README runbook
- [ ] Run the demo end to end and record the real counts
- [ ] Verify each done criterion: re-run is a no-op, threshold failure loads nothing, a broken rule fails the tests
- [ ] Collect the numbered screenshots
- [ ] Document limitations and manual steps honestly
- [ ] Verify a fresh clone follows the README commands from scratch

---

## Adding a new step

Append a new `## N — <name>` section with its own task checklist, add its row to the Overview table, and recompute **Overall** as the new total checked/total across every step. Never mark a step "Done" while an unchecked task remains under it — split the step instead of rounding up.
