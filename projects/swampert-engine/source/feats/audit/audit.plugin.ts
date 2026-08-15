import { Elysia } from "elysia";
import { AuthGuardPlugin } from "@feats/shared/auth.guard.plugin";

import type { TableHistoryUseCase } from "@core/audit/table-history.usecase";
import { HistoryParams, AuditHistoryResponse } from "@feats/audit/audit.schema";

export const AuditPlugin = (tableHistory: TableHistoryUseCase) =>
  new Elysia({ name: "audit.plugin", prefix: "/audit" })
    .use(AuthGuardPlugin)
    .get("/:table/history", ({ params, auth }) => tableHistory.execute(auth!.tenantId, params.table), {
      params: HistoryParams,
      response: AuditHistoryResponse,
    });
