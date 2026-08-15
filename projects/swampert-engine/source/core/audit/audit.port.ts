export interface AuditLogEntry {
  id: string;
  userId: string;
  action: string;
  entityId: string;
  details: Record<string, unknown>;
  occurredAt: Date;
}

export interface AuditPort {
  tableHistory(tenantId: string, tableName: string): Promise<AuditLogEntry[]>;
}
