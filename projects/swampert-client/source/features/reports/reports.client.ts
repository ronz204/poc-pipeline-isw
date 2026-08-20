import { ApiClient, API_BASE_URL } from "@shared/http/api.client";
import { useAuthStore } from "@features/auth/auth.store";

export interface MonthlyExecutionSummaryRow {
  tenantId: string;
  period: string;
  executionCount: number;
  avgDurationSeconds: string | null;
  totalCost: string;
  refreshedAt: string;
}

export interface SwarmTaskSummaryRow {
  tenantId: string;
  swarmId: string;
  taskStatus: string;
  taskCount: number;
  refreshedAt: string;
}

export interface ErrorSummaryRow {
  tenantId: string;
  period: string;
  severity: string;
  errorCount: number;
  refreshedAt: string;
}

export interface RefreshResult {
  status: "accepted";
}

function toPeriodParam(period: Date): string {
  return period.toISOString().slice(0, 10);
}

// Every method here reads the current token from the auth store itself
// (deltas/analytics-dashboard.spec.md § Implementación) rather than taking it
// as a parameter — every call site would otherwise have to thread the token
// through, and this is the one Pinia store this project has.
export class ReportsApiClient extends ApiClient {
  public async monthlyExecutions(period?: Date): Promise<MonthlyExecutionSummaryRow[]> {
    const query = period ? `?period=${toPeriodParam(period)}` : "";
    return this.request<MonthlyExecutionSummaryRow[]>(`/reports/monthly-executions${query}`, {}, this.currentToken());
  }

  public async swarmTasks(swarmId?: string): Promise<SwarmTaskSummaryRow[]> {
    const query = swarmId ? `?swarmId=${swarmId}` : "";
    return this.request<SwarmTaskSummaryRow[]>(`/reports/swarm-tasks${query}`, {}, this.currentToken());
  }

  public async errors(period?: Date): Promise<ErrorSummaryRow[]> {
    const query = period ? `?period=${toPeriodParam(period)}` : "";
    return this.request<ErrorSummaryRow[]>(`/reports/errors${query}`, {}, this.currentToken());
  }

  public async refresh(period: Date): Promise<RefreshResult> {
    return this.request<RefreshResult>("/reports/refresh", {
      method: "POST",
      body: JSON.stringify({ period }),
    }, this.currentToken());
  }

  private currentToken(): string | null {
    return useAuthStore().token;
  }
}

export const reportsApiClient = new ReportsApiClient(API_BASE_URL);
