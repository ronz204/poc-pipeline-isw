import { sql, eq, and } from "drizzle-orm";
import { monthlyExecutionSummary, swarmTaskSummary, errorSummary } from "@elements/reports.element";

import type { Drizzler } from "@database/drizzler.client";
import type {
  ReportsPort, MonthlyExecutionSummaryRow, SwarmTaskSummaryRow, ErrorSummaryRow,
} from "@core/reports/reports.port";

import { TenantScope } from "@helpers/tenant.helper";

export class ReportsRepo implements ReportsPort {
  constructor(
    private readonly db: Drizzler,
    private readonly tenantScope: TenantScope,
  ) {};

  // reports.sp_refresh_reports manages app.current_tenant_id itself, once per
  // tenant, inside its own loop — it needs no caller-side tenant context at all, so
  // this is the one write in this slice that goes straight through the pooled
  // connection with no TenantScope wrapping (deltas/restful.spec.md § Technical
  // context — pre-scoping this call to one tenant would be actively wrong).
  public async refresh(period: Date): Promise<void> {
    // A raw sql`` template bound through .execute() hands the parameter straight to
    // postgres-js's low-level bind, which — unlike drizzle's query builder — has no
    // column-type codec to serialize a JS Date; it has to be a string already.
    await this.db.execute(sql`CALL reports.sp_refresh_reports(${period.toISOString().slice(0, 10)}::date)`);
  };

  public async readMonthlyExecutions(tenantId: string, period?: Date): Promise<MonthlyExecutionSummaryRow[]> {
    return this.tenantScope.run(tenantId, async (tx) => {
      const rows = await tx.select().from(monthlyExecutionSummary)
        .where(period
          ? and(eq(monthlyExecutionSummary.tenantId, tenantId), eq(monthlyExecutionSummary.period, period.toISOString().slice(0, 10)))
          : eq(monthlyExecutionSummary.tenantId, tenantId));

      return rows as MonthlyExecutionSummaryRow[];
    });
  };

  public async readSwarmTasks(tenantId: string, swarmId?: string): Promise<SwarmTaskSummaryRow[]> {
    return this.tenantScope.run(tenantId, async (tx) => {
      const rows = await tx.select().from(swarmTaskSummary)
        .where(swarmId
          ? and(eq(swarmTaskSummary.tenantId, tenantId), eq(swarmTaskSummary.swarmId, swarmId))
          : eq(swarmTaskSummary.tenantId, tenantId));

      return rows as SwarmTaskSummaryRow[];
    });
  };

  public async readErrors(tenantId: string, period?: Date): Promise<ErrorSummaryRow[]> {
    return this.tenantScope.run(tenantId, async (tx) => {
      const rows = await tx.select().from(errorSummary)
        .where(period
          ? and(eq(errorSummary.tenantId, tenantId), eq(errorSummary.period, period.toISOString().slice(0, 10)))
          : eq(errorSummary.tenantId, tenantId));

      return rows as ErrorSummaryRow[];
    });
  };
};
