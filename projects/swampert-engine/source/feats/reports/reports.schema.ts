import { t } from "elysia";

export const RefreshBody = t.Object({
  period: t.Date(),
});

export const RefreshResponse = t.Object({
  status: t.Literal("accepted"),
});

export const MonthlyExecutionsQuery = t.Object({
  period: t.Optional(t.Date()),
});

export const MonthlyExecutionSummaryResponse = t.Array(t.Object({
  tenantId: t.String(),
  period: t.String(),
  executionCount: t.Integer(),
  avgDurationSeconds: t.Union([t.String(), t.Null()]),
  totalCost: t.String(),
  refreshedAt: t.Date(),
}));

export const SwarmTasksQuery = t.Object({
  swarmId: t.Optional(t.String({ format: "uuid" })),
});

export const SwarmTaskSummaryResponse = t.Array(t.Object({
  tenantId: t.String(),
  swarmId: t.String(),
  taskStatus: t.String(),
  taskCount: t.Integer(),
  refreshedAt: t.Date(),
}));

export const ErrorsQuery = t.Object({
  period: t.Optional(t.Date()),
});

export const ErrorSummaryResponse = t.Array(t.Object({
  tenantId: t.String(),
  period: t.String(),
  severity: t.String(),
  errorCount: t.Integer(),
  refreshedAt: t.Date(),
}));
