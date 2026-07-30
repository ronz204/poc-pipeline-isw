import { sql } from "drizzle-orm";
import { timestamp, uuid, type AnyPgColumn } from "drizzle-orm/pg-core";

const tenantId = (ref: () => AnyPgColumn) => uuid("tenant_id")
  .notNull().references(ref, { onDelete: "restrict" });

const optionalTimestamp = (name: string) => timestamp(name, { withTimezone: true });

const requiredTimestamp = (name: string) => timestamp(name, { withTimezone: true })
  .notNull().default(sql`now()`);

export const columns = Object.freeze({
  requiredTimestamp,
  optionalTimestamp,
  tenantId,
});
