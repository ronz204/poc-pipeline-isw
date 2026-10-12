# Sales CSV ETL Run — Spec

> One run of the pipeline over one sales CSV: validate every row, quarantine the invalid ones with their reasons, load the valid ones idempotently into PostgreSQL, reconcile against database state, and audit the outcome.

## Intent

A sales file is untrusted input. The run exists so that every row of it ends in exactly one place: a sale in the destination table, or a rejected record with the reasons it failed. A run that cannot account for its rows fails instead of reporting success, and a re-run of the same file is safe.

## Scope

This slice owns the whole run as one capability: settings loading, extraction, validation, transformation, quarantine, load, reconciliation, run audit, the run report and its evidence files, structured logging, the command line, and the deterministic synthetic dataset generator whose expected outcomes pin the behavior above.

Non-goals:

- No scheduler, orchestrator, alerting, or deployment; each run is launched by hand.
- No volume tuning: the load path is row by row on purpose, because the per-statement affected-row count is what reconciliation uses.
- No configurable rule catalog and no statistical rules; the rules below are fixed in code.
- No date-format guessing and no date range rule: any real calendar date in `YYYY-MM-DD` is valid.
- No content-level idempotency: a row whose identifier already exists is skipped without comparing values.
- No authentication, caching, pagination, or schema migrations.
- Concurrent runs over the same file are unsupported.
- No automatic cleanup of a stale `RUNNING` row: one that outlives its process marks a dead run, and is a documented limitation rather than something the run handles.

## Contract

### Entry points

Two commands on the installed `piper` command: run the pipeline on a CSV, and generate the datasets. The process exits `1` when the run ends `FAILED` and `0` otherwise.

### Settings

Read from environment variables. Database parameters are passed to the driver individually, never assembled into a URL.

| Setting | Default | Meaning |
|---|---|---|
| host / port | `127.0.0.1` / `5432` | Database endpoint |
| user / password / database | none (required) | Database credentials |
| reports directory / logs directory | `reports` / `logs` | Per-run output locations |
| reject-rate threshold | `0.2` | A run fails when the reject rate is strictly above it |
| maximum input size | `50` MB | Larger files are refused before being read |

### Extract

- Refuse a file above the size cap before reading it.
- Read every column as text: empty strings stay empty, a UTF-8 byte-order mark is tolerated, blank lines stay as rows so numbering stays aligned.
- A blank line is a row of empty fields: it is rejected with every `missing_<field>` code, not with `wrong_column_count`.
- The seven required columns are transaction identifier, product, category, quantity, unit price, transaction date, country. A missing required column fails the run. Extra columns are ignored and reported through a log event (column names only).
- The record number of a row is its position plus two (the header is line one).
- A row whose column count differs from the header is always a rejection with `wrong_column_count`: it never aborts the run and is never dropped. Its fields cannot be mapped reliably to columns, so it carries only that code, and its original values are kept in the rejected record.

### Validate

Rules are named checks; the check name is the reason code. All failures of a row are collected, so a row carries every code it violates. An empty or whitespace-only field produces `missing_<field>` and also the field's format code where one exists (empty quantity yields `missing_quantity` and `invalid_quantity`; empty product yields only `missing_product`).

| Reason code | Rule |
|---|---|
| `wrong_column_count` | Row length differs from the header |
| `missing_<field>` | Required field empty or whitespace only; exists for all seven fields |
| `invalid_transaction_id` | Not a positive integer of at most 18 ASCII digits |
| `invalid_quantity` | Not an integer between 1 and 9999 |
| `invalid_unit_price` | Not a decimal with an optional sign, at most 2 decimals and at most 7 integer digits |
| `non_positive_unit_price` | Format-valid price that is zero or negative; evaluated only when the format is valid |
| `invalid_transaction_date` | Not a real calendar date in `YYYY-MM-DD` |
| `duplicate_transaction_id` | Identifier already appeared earlier in the file |

- Numeric patterns use ASCII digits only. The bounds guarantee `total` fits its column.
- Identifier, quantity, price, and date are judged on the original text, without trimming: a value with surrounding whitespace is invalid.
- Leading zeros are allowed in identifiers and quantities (`0007`, `0001`), but an identifier is still at most 18 characters.
- A price needs digits on both sides of the decimal point: `.5` and `5.` are invalid, and `+5.00` is valid.
- Duplicate detection compares identifiers normalized without leading zeros, considers only format-valid identifiers, and keeps the first occurrence whether or not that first row is itself valid.
- A row with no failures is valid; every other row is rejected.

### Transform

Applied to valid rows only:

1. Trim text and collapse internal whitespace.
2. Capitalize each word of category and country using a whitespace-only word split (standard title-casing breaks apostrophes).
3. Convert to integer, exact decimal, and date types.
4. Compute `total = quantity × unit_price` with exact decimal arithmetic.

Capitalizing a word lowercases the rest of it, so `UNITED STATES` becomes `United States` and an acronym such as `USA` becomes `Usa`. A hyphen or apostrophe does not start a new word: `guinea-bissau` becomes `Guinea-bissau`. Product text is trimmed and collapsed but keeps its case.

### Run order and load

1. Create the run identifier and report, open the logger, connect, ensure the schema exists (idempotent).
2. Insert the run as `RUNNING`, committed immediately.
3. Extract, validate; insert rejected records, committed immediately.
4. Compute the reject rate (`rejected / input`, defined as `0` when the input has no data rows). Strictly above the threshold: the run fails and loads nothing.
5. In one transaction: transform, insert sales one by one with a conflict-do-nothing clause, using each statement's affected-row count to separate inserted from already-existing rows.
6. Still in that transaction, reconcile. Any mismatch rolls back every insert of the run and fails it.
7. Final status: `SUCCESS` without rejects, `SUCCESS_WITH_REJECTS` with rejects.
8. In every outcome: close the connection, update the run row (when one exists), write the report files, log the result.

All SQL is parameterized. The persistence model (`etl_runs`, `sales`, `rejected_records`) and its `CHECK` constraints are defined in the project's database reference.

### Reconciliation

- `rows_in = rows_valid + rows_rejected`
- `rows_valid = rows_loaded + rows_skipped_existing`
- The database confirms it: the count of this batch's identifiers in `sales` equals `rows_valid`, and the count of sales tagged with this run equals `rows_loaded`.

### Run status

`RUNNING` while in flight, then `SUCCESS`, `SUCCESS_WITH_REJECTS`, or `FAILED`.

An input with a header and zero data rows ends `SUCCESS` with all counts `0`.

Failures that occur before rows can be counted (missing file, missing required column, file above the size cap, database unreachable, reports or logs directory not writable) end `FAILED` with row counts `null` (not `0`) in both the report and the run row, `reconciled` false, and `error` carrying the reason. Report files are still written when the database is unreachable; there is no run row in that case.

### Run report

```json
{
  "run_id": "20250101T120000-a1b2c3",
  "source_file": "data/sales_valid.csv",
  "status": "SUCCESS",
  "rows_in": 1000, "rows_valid": 1000, "rows_rejected": 0,
  "rows_loaded": 1000, "rows_skipped_existing": 0,
  "rejection_breakdown": {},
  "reconciled": true,
  "duration_ms": 0,
  "error": null
}
```

Outputs per run: a JSON file, a Markdown summary on standard output, and, only when there are rejects, a CSV of rejected rows with their reasons. In the CSV, any cell starting with `=`, `+`, `-`, `@`, tab, or carriage return is prefixed with an apostrophe. File names derive only from the generated run identifier.

### Logging

The run identifier is bound once and attached to every event. Output goes to a readable console stream and a JSON Lines file per run. Events: run started, extract done, extra columns, validate done, rows rejected, transform done, load done, reconcile done, run finished, run failed. Events carry counts and reason codes only, never row values.

### Synthetic dataset generator

Deterministic: a fixed seed produces the same files every time. Dates fall within calendar year 2025.

| Dataset | Content |
|---|---|
| Clean | 1000 valid rows, about 8 percent with messy but valid text so the transform has visible work |
| Defective | Same generator over a disjoint identifier range, with planted defects at fixed positions: 3 non-positive prices, 2 missing products, 2 duplicate identifiers, 2 invalid dates, 2 invalid quantities, 1 malformed price. Yields 12 rejections and 988 valid rows |

The disjoint identifier ranges let both files load into the same database (1988 sales).

## Invariants

- Every input row ends in exactly one place: a sale (loaded or skipped as already existing) or a rejected record. Nothing is dropped or loaded silently.
- The reconciliation equalities hold on every run that reports success; a mismatch rolls the load back and fails the run.
- A reject rate strictly above the threshold fails the run with zero sales inserted; the rejected records are still committed. A rate equal to the threshold passes.
- Re-running the same file inserts nothing new: all valid rows are counted as skipped and the sales count is unchanged.
- The load is all-or-nothing. The `RUNNING` row and quarantine are committed independently of the load transaction, so a failed run keeps its trace and its evidence.
- Duplicate detection normalizes the identifier without leading zeros; the first occurrence wins.
- Every validation rule is mirrored by a database `CHECK`; a defect in application code cannot persist an out-of-range value.
- Money is exact decimal end to end, never floating point.
- No data from the CSV is concatenated into SQL.
- Logs and reports carry counts and codes only; raw values exist only in the rejected-records table and the quarantine CSV.
- Every outcome ends with the final run-row update (when a row exists), the report files, and a log event. Exit code is `1` if and only if the status is `FAILED`.
- Timestamps are UTC.

## Deferred / Open questions

None. Everything left open earlier was either decided above or moved out of this contract (validation mechanism: project structure reference; output directory permissions: container work).

## Acceptance criteria

- The clean dataset loads 1000 of 1000 rows, ends `SUCCESS`, and `reconciled` is true.
- The defective dataset yields 988 valid and 12 rejected with the breakdown listed under the generator, ends `SUCCESS_WITH_REJECTS`, and the database holds 1988 sales after both files are loaded.
- A second run of the clean dataset loads 0 rows, skips 1000, and leaves the sales count unchanged.
- With the threshold set below the defective dataset's reject rate, the run ends `FAILED`, no sale of that run exists, and its rejected records are in the database.
- A file with a header and no data rows ends `SUCCESS` with zero counts; a reject rate exactly equal to the threshold does not fail the run.
- An empty required field yields both `missing_<field>` and the field's format code where one exists; `-5.00` and `0.00` yield only `non_positive_unit_price`; `1.234` yields only `invalid_unit_price`.
- Unit tests cover each reason code and its boundary cases; a property test shows valid plus rejected equals input for arbitrary input.
- Integration tests on a real PostgreSQL cover: valid file, defective file, idempotent re-run, threshold failure, missing column, missing file, database down. They fail, not skip, when the database is absent.
- A file with one short row and one long row yields two rejections with `wrong_column_count`, and the remaining rows load.
- Breaking a validation rule on purpose makes the suite fail.
- Early failures report `null` row counts and exit with code `1`; an unwritable reports or logs directory is one of them, with a clear error.

---

Last updated: 2026-10-11.
