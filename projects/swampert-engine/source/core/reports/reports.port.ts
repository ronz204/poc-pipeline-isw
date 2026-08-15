export interface MonthlyExecutionSummaryRow {
  tenantId: string;
  period: string;
  executionCount: number;
  avgDurationSeconds: string | null;
  totalCost: string;
  refreshedAt: Date;
}

export interface SwarmTaskSummaryRow {
  tenantId: string;
  swarmId: string;
  taskStatus: string;
  taskCount: number;
  refreshedAt: Date;
}

export interface ErrorSummaryRow {
  tenantId: string;
  period: string;
  severity: string;
  errorCount: number;
  refreshedAt: Date;
}

export interface ReportsPort {
  refresh(period: Date): Promise<void>;
  readMonthlyExecutions(tenantId: string, period?: Date): Promise<MonthlyExecutionSummaryRow[]>;
  readSwarmTasks(tenantId: string, swarmId?: string): Promise<SwarmTaskSummaryRow[]>;
  readErrors(tenantId: string, period?: Date): Promise<ErrorSummaryRow[]>;
}
