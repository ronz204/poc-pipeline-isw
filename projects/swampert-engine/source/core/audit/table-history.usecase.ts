import type { AuditPort, AuditLogEntry } from "@core/audit/audit.port";

export class TableHistoryUseCase {
  constructor(private readonly port: AuditPort) {};

  public execute(tenantId: string, tableName: string): Promise<AuditLogEntry[]> {
    return this.port.tableHistory(tenantId, tableName);
  };
};
