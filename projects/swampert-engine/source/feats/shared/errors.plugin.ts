import { Elysia } from "elysia";
import postgres from "postgres";

const { PostgresError } = postgres;

// Every business rule in this API lives in a PL/pgSQL RAISE EXCEPTION, not in
// TypeScript (deltas/restful.spec.md § Objective) — this is the one place that
// translates a routine's ERRCODE into the HTTP status the caller actually sees.
// Codes not listed here are genuinely unexpected (a bug, not a rejected input),
// so they fall through to Elysia's default 500 handling instead of guessing.
const STATUS_BY_SQLSTATE: Record<string, number> = {
  "22004": 400, // null_value_not_allowed
  "23514": 400, // check_violation
  "P0002": 404, // no_data_found
  "23505": 409, // unique_violation
  "23503": 409, // foreign_key_violation
};

export const ErrorsPlugin = new Elysia({ name: "errors.plugin" })
  .onError({ as: "global" }, ({ error, set }) => {
    // drizzle-orm never throws the driver's PostgresError directly — every
    // .execute()/CALL failure arrives wrapped in a DrizzleQueryError, with the
    // real PostgresError one level down as .cause (verified against a live
    // Postgres: `error instanceof PostgresError` alone never matched here).
    const cause = "cause" in (error as object) ? (error as { cause?: unknown }).cause : undefined;
    const pgError = error instanceof PostgresError
      ? error
      : cause instanceof PostgresError ? cause : null;

    if (!pgError) return;

    set.status = STATUS_BY_SQLSTATE[pgError.code] ?? 500;
    return { error: pgError.message };
  });
