import { sql, type SQL } from "drizzle-orm";

// drizzle-orm's postgres-js execute() path passes JS array params straight through
// to postgres.js's client.unsafe(), which — unlike postgres.js's own tagged
// template — does not serialize a JS array into Postgres array syntax; the
// procedures in drizzle/customs/funcs/*.proc.sql take text[]/uuid[] parameters, so
// every array argument this API sends has to be built as an explicit
// ARRAY[$1, $2, ...] SQL fragment instead of interpolated directly.
export function sqlArray(values: readonly unknown[]): SQL {
  if (values.length === 0) return sql`ARRAY[]`;
  return sql`ARRAY[${sql.join(values.map((value) => sql`${value}`), sql`, `)}]`;
}
