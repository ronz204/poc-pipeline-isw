import { useRouter } from "vue-router";
import { ApiError } from "@shared/http/api.client";
import { useAuthStore } from "@features/auth/auth.store";
import { clearTenantLabel } from "@features/auth/tenantLabel";

import {
  reportsApiClient,
  type MonthlyExecutionSummaryRow,
  type SwarmTaskSummaryRow,
  type ErrorSummaryRow,
  type RefreshResult,
} from "@features/reports/reports.client";

export interface ReportsDataApi {
  fetchMonthlyExecutions(): Promise<MonthlyExecutionSummaryRow[]>;
  fetchSwarmTasks(): Promise<SwarmTaskSummaryRow[]>;
  fetchErrors(): Promise<ErrorSummaryRow[]>;
  refreshReports(period: Date): Promise<RefreshResult>;
  logout(): Promise<void>;
}

// Module-level (not inside useReportsData()) so it survives across separate calls
// from KpisView/TrendsView — that's what lets both share one network request per
// /dashboard/* load instead of duplicating it (spec §7.e). Keyed by tenantId, never
// a single bare array: a same-tab login as a different tenant must never resolve to
// the previous tenant's cached rows.
const monthlyExecutionsCache = new Map<string, MonthlyExecutionSummaryRow[]>();

// The single exit point both the automatic 401 handler and DashboardLayout's manual
// "Cerrar sesión" button call (spec §7.c/f) — one code path, not two implementations
// that could drift apart.
export function useReportsData(): ReportsDataApi {
  const router = useRouter();
  const authStore = useAuthStore();

  async function logout(): Promise<void> {
    authStore.logout();
    monthlyExecutionsCache.clear();
    clearTenantLabel();
    await router.push({ name: "login" });
  }

  // Wraps every ReportsApiClient call: a 401 here means the JWT is missing/expired
  // (ApiClient already attaches it) — the whole session is invalid, not just this
  // one request, so it always routes through the same logout() above rather than
  // letting each view decide how to react to a stale token.
  async function callGuarded<T>(operation: () => Promise<T>): Promise<T> {
    try {
      return await operation();
    } catch (error) {
      if (error instanceof ApiError && error.status === 401) {
        await logout();
      }

      throw error;
    }
  }

  async function fetchMonthlyExecutions(): Promise<MonthlyExecutionSummaryRow[]> {
    const tenantId = authStore.tenantId;
    const cached = tenantId ? monthlyExecutionsCache.get(tenantId) : undefined;
    if (cached) return cached;

    const rows = await callGuarded(() => reportsApiClient.monthlyExecutions());
    if (tenantId) monthlyExecutionsCache.set(tenantId, rows);

    return rows;
  }

  function fetchSwarmTasks(): Promise<SwarmTaskSummaryRow[]> {
    return callGuarded(() => reportsApiClient.swarmTasks());
  }

  function fetchErrors(): Promise<ErrorSummaryRow[]> {
    return callGuarded(() => reportsApiClient.errors());
  }

  // sp_refresh_reports recalculates every tenant's period in one CALL (deltas/reports.spec.md)
  // — clearing the whole cache, not just the current tenant's entry, matches that real
  // scope: any tenant's next fetchMonthlyExecutions() must hit the network again.
  async function refreshReports(period: Date): Promise<RefreshResult> {
    const result = await callGuarded(() => reportsApiClient.refresh(period));
    monthlyExecutionsCache.clear();
    return result;
  }

  return { fetchMonthlyExecutions, fetchSwarmTasks, fetchErrors, refreshReports, logout };
}
