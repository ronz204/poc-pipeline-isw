import { t } from "elysia";

export const LaunchExecutionBody = t.Object({
  taskId: t.String({ format: "uuid" }),
  maxAttempts: t.Optional(t.Integer({ minimum: 1 })),
});

export const CompleteExecutionParams = t.Object({
  id: t.String({ format: "uuid" }),
});

export const CompleteExecutionBody = t.Object({
  status: t.Union([t.Literal("completed"), t.Literal("failed")]),
  maxAttempts: t.Optional(t.Integer({ minimum: 1 })),
});

export const RecordStepParams = t.Object({
  id: t.String({ format: "uuid" }),
});

export const RecordStepBody = t.Object({
  agentId: t.String({ format: "uuid" }),
  reasoning: t.Optional(t.Record(t.String(), t.Unknown())),
  toolsUsed: t.Optional(t.Array(t.String())),
  inputTokens: t.Integer({ minimum: 0 }),
  outputTokens: t.Integer({ minimum: 0 }),
  costPer1kInput: t.Number({ minimum: 0 }),
  costPer1kOutput: t.Number({ minimum: 0 }),
});

export const ExecutionResponse = t.Object({
  id: t.String(),
  tenantId: t.String(),
  taskId: t.String(),
  attemptNumber: t.Integer(),
  status: t.Union([
    t.Literal("pending"), t.Literal("running"), t.Literal("completed"), t.Literal("failed"),
  ]),
  startedAt: t.Date(),
  finishedAt: t.Union([t.Date(), t.Null()]),
});

export const ExecutionStepResponse = t.Object({
  id: t.String(),
  executionId: t.String(),
  agentId: t.String(),
  stepNumber: t.Integer(),
  toolsUsed: t.Array(t.String()),
  occurredAt: t.Date(),
});
