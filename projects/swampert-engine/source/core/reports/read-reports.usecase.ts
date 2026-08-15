import type {
  ReportsPort, MonthlyExecutionSummaryRow, SwarmTaskSummaryRow, ErrorSummaryRow,
} from "@core/reports/reports.port";

export class ReadReportsUseCase {
  constructor(private readonly port: ReportsPort) {};

  public monthlyExecutions(tenantId: string, period?: Date): Promise<MonthlyExecutionSummaryRow[]> {
    return this.port.readMonthlyExecutions(tenantId, period);
  };

  public swarmTasks(tenantId: string, swarmId?: string): Promise<SwarmTaskSummaryRow[]> {
    return this.port.readSwarmTasks(tenantId, swarmId);
  };

  public errors(tenantId: string, period?: Date): Promise<ErrorSummaryRow[]> {
    return this.port.readErrors(tenantId, period);
  };
};
