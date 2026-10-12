# Modules

What each pipeline component does, step by step, and the data it exchanges. Why the system exists lives elsewhere; this file is behavior only.

---

## Configuration

**Purpose.** Reads runtime settings from environment variables so the same code runs locally, in containers, and in CI.

**Flow.**
1. Database connection parameters come from separate variables (host, port, user, password, database name) and are passed to the driver as individual parameters, never assembled into a URL.
2. Output directories, the reject-rate threshold, and the maximum input size have defaults and can be overridden.

**Data shape.**

| Setting | Default | Meaning |
|---|---|---|
| host / port | `localhost` / `5432` | Database endpoint |
| user / password / database | none (required) | Database credentials |
| reports directory / logs directory | `reports` / `logs` | Per-run output locations |
| reject-rate threshold | `0.2` | Share of rejected rows above which a run fails |
| maximum input size | `50` MB | Larger files are refused before being read |

## Extract

**Purpose.** Reads the source CSV exactly as text.

**Flow.**
1. Refuse the file if it exceeds the maximum input size.
2. Read every column as string, keep empty strings as empty (no NA coercion), tolerate a UTF-8 byte-order mark, and keep blank lines as rows so record numbering stays aligned.
3. Fail with a schema error if a required column is missing. Extra columns are ignored and reported through a log event.
4. Rows whose column count differs from the header become rejections (`wrong_column_count`, the only code they carry) rather than aborting the run or being dropped.

**Data shape.** A table of strings with the seven required columns. The record number of a row is its position plus two (the header is line one); it matches the physical file line unless quoted fields span lines.

## Validate

**Purpose.** Applies the declared quality rules to every row and attaches every violated reason code to it.

**Flow.**
1. Rules are declared as a schema of named checks; each check's name is the reason code. The schema is evaluated lazily so all failures are collected in one pass.
2. Failures are grouped per row into a list of reason codes.
3. Duplicate detection runs on the identifier normalized without leading zeros; the first occurrence is kept, whether or not that first row is itself valid.
4. Rows with no failures are valid; the rest are rejected.

**Data shape.**

| Reason code | Rule |
|---|---|
| `wrong_column_count` | Row length differs from the header |
| `missing_<field>` | Required field empty or whitespace only (all seven fields) |
| `invalid_transaction_id` | Not a positive integer of at most 18 ASCII digits |
| `invalid_quantity` | Not an integer between 1 and 9999 |
| `invalid_unit_price` | Not a decimal with an optional sign, at most 2 decimals and 7 integer digits |
| `non_positive_unit_price` | Format-valid price that is zero or negative |
| `invalid_transaction_date` | Not a real calendar date in `YYYY-MM-DD` |
| `duplicate_transaction_id` | Identifier already appeared earlier in the file |

All numeric patterns use ASCII digits only. The bounds guarantee that `total` fits its column.

## Transform

**Purpose.** Normalizes valid rows into typed values.

**Flow.**
1. Trim text and collapse internal whitespace.
2. Capitalize each word of category and country with a whitespace-only word split, because the standard title-casing breaks apostrophes.
3. Convert to integer, exact decimal, and date types.
4. Compute `total = quantity × unit_price` with exact decimal arithmetic.

## Load

**Purpose.** Persists audit rows, quarantined rows, and sales.

**Flow.**
1. Ensure the schema exists (idempotent).
2. Insert the run as `RUNNING` before any work, committed immediately.
3. Insert rejected records, committed immediately, so quarantine survives a failed run.
4. Inside one transaction, insert sales one by one with a conflict-do-nothing clause, using each statement's affected-row count to separate inserted from already-existing rows.
5. Still inside the transaction, reconcile (see Pipeline); any mismatch rolls the whole load back.
6. Update the run row with final status, counts, breakdown, duration, and error.

**Dependencies.** All statements are parameterized.

## Pipeline

**Purpose.** Orchestrates one run and translates any failure into a recorded `FAILED` status.

**Flow.**
1. Create the run identifier and report, open the logger, connect, ensure schema, record `RUNNING`.
2. Extract, validate, quarantine rejected rows.
3. Compute the reject rate; above the threshold, raise and load nothing.
4. Transform and load inside one transaction.
5. Reconcile: input equals valid plus rejected; valid equals loaded plus skipped; and the database confirms it, by counting the batch's identifiers in the sales table (must equal valid) and the rows tagged with this run (must equal loaded).
6. Set the final status: `SUCCESS` without rejects, `SUCCESS_WITH_REJECTS` with rejects.
7. In every case, close the connection, update the run row, write report files, and log the result. A database that is unreachable still produces a failed report.

## Run report

**Purpose.** The end-of-run summary shared by the audit row, the JSON file, the console, and CI.

**Data shape.**

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

Outputs per run: a JSON file, a Markdown summary printed to standard output, and, only when there are rejects, a CSV of rejected rows with their reasons. The CSV neutralizes spreadsheet formulas: any cell starting with `=`, `+`, `-`, `@`, tab, or carriage return is prefixed with an apostrophe.

## Logging

**Purpose.** Structured events for each run.

**Flow.** The run identifier is bound once and attached to every event. Output goes to a readable console stream and a JSON Lines file per run. Events: run started, extract done, extra columns, validate done, rows rejected, transform done, load done, reconcile done, run finished, run failed. Events carry counts and reason codes only, never row values.

## Synthetic data generator

**Purpose.** Produces the two deterministic datasets.

**Flow.** A fixed seed builds 1000 clean rows (about 8 percent with messy but valid text so the transform has visible work). The defective dataset reuses the generator with a different identifier range and applies explicit planted defects at fixed positions, so its expected rejections are known: 12 rejections (3 non-positive prices, 2 missing products, 2 duplicate identifiers, 2 invalid dates, 2 invalid quantities, 1 malformed price) and 988 valid rows. The disjoint identifier ranges let both files load into the same database (1988 sales).

## Command line

**Purpose.** The user-facing entry point.

**Flow.** Two commands: run the pipeline on a CSV, and generate the datasets. The process exits with code 1 when the run ends `FAILED` and 0 otherwise, so CI turns red on failure.

---

## Non-goals

- Components do not talk to each other through files or queues; a run is a single in-process sequence.
