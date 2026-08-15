import { Elysia } from "elysia";
import { AuthGuardPlugin } from "@feats/shared/auth.guard.plugin";

import type { RefreshReportsUseCase } from "@core/reports/refresh-reports.usecase";
import type { ReadReportsUseCase } from "@core/reports/read-reports.usecase";

import {
  RefreshBody, RefreshResponse, MonthlyExecutionsQuery, MonthlyExecutionSummaryResponse,
  SwarmTasksQuery, SwarmTaskSummaryResponse, ErrorsQuery, ErrorSummaryResponse,
} from "@feats/reports/reports.schema";

export interface ReportsUseCases {
  refreshReports: RefreshReportsUseCase;
  readReports: ReadReportsUseCase;
}

export const ReportsPlugin = (usecases: ReportsUseCases) =>
  new Elysia({ name: "reports.plugin", prefix: "/reports" })
    .use(AuthGuardPlugin)
    .post("/refresh", async ({ body }) => {
      await usecases.refreshReports.execute(body.period);
      return { status: "accepted" as const };
    }, {
      body: RefreshBody,
      response: RefreshResponse,
    })
    .get("/monthly-executions", ({ query, auth }) =>
      usecases.readReports.monthlyExecutions(auth!.tenantId, query.period), {
      query: MonthlyExecutionsQuery,
      response: MonthlyExecutionSummaryResponse,
    })
    .get("/swarm-tasks", ({ query, auth }) =>
      usecases.readReports.swarmTasks(auth!.tenantId, query.swarmId), {
      query: SwarmTasksQuery,
      response: SwarmTaskSummaryResponse,
    })
    .get("/errors", ({ query, auth }) =>
      usecases.readReports.errors(auth!.tenantId, query.period), {
      query: ErrorsQuery,
      response: ErrorSummaryResponse,
    });
