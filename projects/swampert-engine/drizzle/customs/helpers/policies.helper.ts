import { sql } from "drizzle-orm";
import { backuper } from "@elements/roles.element";
import { pgPolicy, type AnyPgColumn } from "drizzle-orm/pg-core";

export const tenantIsolationPolicy = (tenantIdColumn: AnyPgColumn) =>
  pgPolicy("tenant_isolation", {
    as: "permissive",
    for: "all",
    using: sql`${tenantIdColumn} = current_setting('app.current_tenant_id', true)::uuid`,
    withCheck: sql`${tenantIdColumn} = current_setting('app.current_tenant_id', true)::uuid`,
  });

export const backupReadablePolicy = () =>
  pgPolicy("backup_read", {
    as: "permissive",
    for: "select",
    to: backuper,
    using: sql`true`
  });

export const policies = Object.freeze({
  tenantIsolationPolicy,
  backupReadablePolicy,
});
