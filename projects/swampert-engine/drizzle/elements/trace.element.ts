import { tenants, users } from "@elements/auth.element";
import { columns } from "@customs/helpers/column.helper";
import { executions, agents } from "@elements/core.element";
import { policies } from "@customs/helpers/policies.helper";

import {
  pgSchema, uuid, text, jsonb, integer,
  numeric, index,
} from "drizzle-orm/pg-core";

export const trace = pgSchema("trace");

export const errorSeverity = trace.enum("error_severity", ["low", "medium", "high", "critical"]);

export const executionSteps = trace.table.withRLS("execution_steps",
  {
    id: uuid("id").primaryKey(),
    tenantId: columns.tenantId(() => tenants.id),
    executionId: uuid("execution_id").notNull()
      .references(() => executions.id, { onDelete: "restrict" }),
    agentId: uuid("agent_id").notNull()
      .references(() => agents.id, { onDelete: "restrict" }),
    stepNumber: integer("step_number").notNull(),
    reasoning: jsonb("reasoning").notNull().default({}),
    toolsUsed: text("tools_used").array().notNull().default([]),
    occurredAt: columns.requiredTimestamp("occurred_at"),
    deletedAt: columns.optionalTimestamp("deleted_at"),
  }, (t) => [
    index("execution_steps_tenant_id_idx").on(t.tenantId),
    index("execution_steps_execution_id_step_number_idx").on(t.executionId, t.stepNumber),
    index("execution_steps_reasoning_gin_idx").using("gin", t.reasoning),
    policies.tenantIsolationPolicy(t.tenantId),
    policies.backupReadablePolicy(),
  ]);

export const tokenCosts = trace.table.withRLS("token_costs",
  {
    id: uuid("id").primaryKey(),
    tenantId: columns.tenantId(() => tenants.id),
    executionId: uuid("execution_id").notNull()
      .references(() => executions.id, { onDelete: "restrict" }),
    stepId: uuid("step_id")
      .references(() => executionSteps.id, { onDelete: "restrict" }),
    inputTokens: integer("input_tokens").notNull(),
    outputTokens: integer("output_tokens").notNull(),
    estimatedCost: numeric("estimated_cost", { precision: 10, scale: 4 }).notNull(),
    recordedAt: columns.requiredTimestamp("recorded_at"),
    deletedAt: columns.optionalTimestamp("deleted_at"),
  }, (t) => [
    index("token_costs_tenant_id_idx").on(t.tenantId),
    index("token_costs_execution_id_idx").on(t.executionId),
    policies.tenantIsolationPolicy(t.tenantId),
    policies.backupReadablePolicy(),
  ]);

export const executionErrors = trace.table.withRLS("execution_errors",
  {
    id: uuid("id").primaryKey(),
    tenantId: columns.tenantId(() => tenants.id),
    executionId: uuid("execution_id").notNull()
      .references(() => executions.id, { onDelete: "restrict" }),
    stepId: uuid("step_id")
      .references(() => executionSteps.id, { onDelete: "restrict" }),
    errorType: text("error_type").notNull(),
    message: text("message").notNull(),
    severity: errorSeverity("severity").notNull(),
    occurredAt: columns.requiredTimestamp("occurred_at"),
    deletedAt: columns.optionalTimestamp("deleted_at"),
  }, (t) => [
    index("execution_errors_tenant_id_idx").on(t.tenantId),
    index("execution_errors_execution_id_idx").on(t.executionId),
    index("execution_errors_severity_idx").on(t.severity),
    policies.tenantIsolationPolicy(t.tenantId),
    policies.backupReadablePolicy(),
  ]);

export const auditLog = trace.table.withRLS("audit_log",
  {
    id: uuid("id").primaryKey(),
    tenantId: columns.tenantId(() => tenants.id),
    userId: uuid("user_id").notNull()
      .references(() => users.id, { onDelete: "restrict" }),
    action: text("action").notNull(),
    entityType: text("entity_type").notNull(),
    entityId: uuid("entity_id").notNull(),
    details: jsonb("details").notNull().default({}),
    occurredAt: columns.requiredTimestamp("occurred_at"),
  }, (t) => [
    index("audit_log_tenant_id_occurred_at_idx").on(t.tenantId, t.occurredAt),
    policies.tenantIsolationPolicy(t.tenantId),
    policies.backupReadablePolicy(),
  ]);
