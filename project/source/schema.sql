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
