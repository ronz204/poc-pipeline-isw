# Database

The PostgreSQL data model, its invariants, and how the pipeline talks to it.

---

## Access control

| Role | Purpose | Used by |
|---|---|---|
| Application user | Creates the schema if missing and reads/writes all three tables | The pipeline and the integration tests |

One role does both DDL and DML because the pipeline bootstraps its own schema on every start. This is a demo-scale simplification; a real deployment would split a migration role from a runtime role without DDL rights. The database port is published on the loopback interface only.

## Data model

```sql
-- Idempotent: safe to run on every pipeline start.
CREATE TABLE IF NOT EXISTS etl_runs (
    run_id                TEXT PRIMARY KEY,
    source_file           TEXT        NOT NULL,
    status                TEXT        NOT NULL
        CHECK (status IN ('RUNNING', 'SUCCESS', 'SUCCESS_WITH_REJECTS', 'FAILED')),
    started_at            TIMESTAMPTZ NOT NULL,
    finished_at           TIMESTAMPTZ,
    duration_ms           INTEGER,
    rows_in               INTEGER,
    rows_valid            INTEGER,
    rows_rejected         INTEGER,
    rows_loaded           INTEGER,
    rows_skipped_existing INTEGER,
    rejection_breakdown   JSONB,
    error_message         TEXT
);

CREATE TABLE IF NOT EXISTS sales (
    transaction_id   BIGINT PRIMARY KEY,
    product          TEXT          NOT NULL,
    category         TEXT          NOT NULL,
    quantity         INTEGER       NOT NULL CHECK (quantity BETWEEN 1 AND 9999),
    unit_price       NUMERIC(12,2) NOT NULL CHECK (unit_price > 0 AND unit_price <= 9999999.99),
    total            NUMERIC(14,2) NOT NULL CHECK (total = quantity * unit_price),
    transaction_date DATE          NOT NULL,
    country          TEXT          NOT NULL,
    loaded_by_run    TEXT          NOT NULL REFERENCES etl_runs (run_id)
);

CREATE TABLE IF NOT EXISTS rejected_records (
    id            BIGSERIAL PRIMARY KEY,
    run_id        TEXT    NOT NULL REFERENCES etl_runs (run_id),
    record_number INTEGER NOT NULL,
    reasons       TEXT[]  NOT NULL CHECK (cardinality(reasons) > 0),
    raw           JSONB   NOT NULL
);
```

| Table | Holds |
|---|---|
| `etl_runs` | One audit row per run: status, counts, breakdown snapshot, duration, error |
| `sales` | Validated transactions; `loaded_by_run` gives basic lineage |
| `rejected_records` | Quarantine: one row per rejected source row, with every reason code and the original values |

The rejection breakdown can also be derived from quarantine: `SELECT r, COUNT(*) FROM rejected_records, unnest(reasons) r WHERE run_id = … GROUP BY r`. The `etl_runs` column is a snapshot taken when the run finished.

## Persistence invariants

- **No invalid value persists:** the validation rules are repeated as `CHECK` constraints (quantity range, positive bounded price, `total = quantity × unit_price`, non-empty reasons), so a defect in application code still cannot store an out-of-range value.
- **One sale per transaction identifier:** the primary key plus `ON CONFLICT DO NOTHING` makes re-running a file idempotent. The guarantee is by identifier only; an existing identifier with different values is skipped, not updated.
- **Every sale and every rejection belongs to a run:** foreign keys to `etl_runs` mean the run row must exist first, which is why the `RUNNING` row is inserted before anything else.
- **Quarantine survives failure:** rejected records are committed independently of the load transaction, so a run failed by the reject-rate threshold still keeps its evidence.
- **Loads are all-or-nothing:** all sale inserts and the reconciliation queries share one transaction; a failed reconciliation rolls back every insert of that run.
- **Money is exact:** prices and totals are `NUMERIC`, never floating point.

## Infrastructure

- PostgreSQL 17 (alpine) in a Compose service with a `pg_isready` healthcheck; the pipeline service waits for it.
- Data persists in a named volume; removing the volumes resets the database, which is how demos start from scratch.
- No backup, replication, or high availability: the database is disposable demo infrastructure.
- Credentials come from an env file kept out of version control.

## Access patterns

- Every statement is parameterized; no CSV-derived text is concatenated into SQL.
- The schema is created on each start with `IF NOT EXISTS` statements; there is no migration tool.
- The run row is inserted and quarantine written in autocommit mode; the sale inserts and reconciliation run inside an explicit transaction.
- Sales are inserted row by row, because the per-statement affected-row count is what separates newly inserted rows from already-existing ones for reconciliation. At larger volume this would become a bulk copy into a staging table.
- Reconciliation reads: the count of the batch's identifiers in `sales` must equal the number of valid rows, and the count of rows tagged with the current run must equal the number inserted.

---

## Non-goals

- No schema migrations, partitioning, or archival: the data volume does not call for them.
