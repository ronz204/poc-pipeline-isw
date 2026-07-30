import { sql } from "drizzle-orm";
import { timestamp, uuid } from "drizzle-orm/pg-core";
import { type AnyPgColumn } from "drizzle-orm/pg-core";

const tenantId = (ref: () => AnyPgColumn) => uuid("tenant_id")
  .notNull().references(ref, { onDelete: "restrict" });

const deletedAt = () => timestamp("deleted_at", { withTimezone: true })
const createdAt = () => timestamp("created_at", { withTimezone: true })
  .notNull().default(sql`now()`);

export const columns = Object.freeze({
  createdAt, deletedAt,
  tenantId,
});
