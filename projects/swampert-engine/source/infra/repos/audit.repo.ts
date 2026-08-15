import { sql } from "drizzle-orm";

import type { Drizzler } from "@database/drizzler.client";
import type { AuditPort, AuditLogEntry } from "@core/audit/audit.port";

import { TenantScope } from "@helpers/tenant.helper";

interface AuditHistoryRow {
  id: string;
  user_id: string;
  action: string;
  entity_id: string;
  details: Record<string, unknown>;
  occurred_at: string;
}

export class AuditRepo implements AuditPort {
  constructor(
    private readonly db: Drizzler,
    private readonly tenantScope: TenantScope,
  ) {};

  // trace.fn_table_history is not SECURITY DEFINER — it runs as the caller (runner),
  // so it's tenant-scoped by the ordinary tenant_isolation policy on
  // trace.audit_log, same as any direct SELECT against a tenant-scoped table.
  public async tableHistory(tenantId: string, tableName: string): Promise<AuditLogEntry[]> {
    return this.tenantScope.run(tenantId, async (tx) => {
      const result = await tx.execute(
        sql`SELECT * FROM trace.fn_table_history(${tableName}::text)`);

      return (result as unknown as AuditHistoryRow[]).map((row) => ({
        id: row.id,
        userId: row.user_id,
        action: row.action,
        entityId: row.entity_id,
        details: row.details,
        occurredAt: new Date(row.occurred_at),
      }));
    });
  };
};
