import { sql } from "drizzle-orm";
import { pgSchema, uuid, text, jsonb, integer, numeric, timestamp, index, pgPolicy } from "drizzle-orm/pg-core";
import { backuper } from "./roles.element";
import { tenants, users } from "./auth.element";
import { executions, agents } from "./core.element";

export const trace = pgSchema("trace");

export const errorSeverity = trace.enum("error_severity", ["low", "medium", "high", "critical"]);

const tenantIsolationPolicy = (t: { tenantId: unknown }) =>
  pgPolicy("tenant_isolation", {
    as: "permissive",
    for: "all",
    using: sql`${t.tenantId} = current_setting('app.current_tenant_id', true)::uuid`,
    withCheck: sql`${t.tenantId} = current_setting('app.current_tenant_id', true)::uuid`,
  });

const backupReadPolicy = () =>
  pgPolicy("backup_read", {
    as: "permissive",
    for: "select",
    to: backuper,
    using: sql`true`,
  });

export const executionSteps = trace.table.withRLS(
  "execution_steps",
  {
    id: uuid("id").primaryKey(),
    tenantId: uuid("tenant_id")
      .notNull()
      .references(() => tenants.id, { onDelete: "restrict" }),
    executionId: uuid("execution_id")
      .notNull()
      .references(() => executions.id, { onDelete: "restrict" }),
    agentId: uuid("agent_id")
      .notNull()
      .references(() => agents.id, { onDelete: "restrict" }),
    stepNumber: integer("step_number").notNull(),
    reasoning: jsonb("reasoning").notNull().default({}),
    toolsUsed: text("tools_used").array().notNull().default([]),
    occurredAt: timestamp("occurred_at", { withTimezone: true }).notNull().default(sql`now()`),
    deletedAt: timestamp("deleted_at", { withTimezone: true }),
  },
  (t) => [
    index("execution_steps_tenant_id_idx").on(t.tenantId),
    index("execution_steps_execution_id_step_number_idx").on(t.executionId, t.stepNumber),
    index("execution_steps_reasoning_gin_idx").using("gin", t.reasoning),
    tenantIsolationPolicy(t),
    backupReadPolicy(),
  ],
);

export const tokenCosts = trace.table.withRLS(
  "token_costs",
  {
    id: uuid("id").primaryKey(),
    tenantId: uuid("tenant_id")
      .notNull()
      .references(() => tenants.id, { onDelete: "restrict" }),
    executionId: uuid("execution_id")
      .notNull()
      .references(() => executions.id, { onDelete: "restrict" }),
    stepId: uuid("step_id").references(() => executionSteps.id, { onDelete: "restrict" }),
    inputTokens: integer("input_tokens").notNull(),
    outputTokens: integer("output_tokens").notNull(),
    estimatedCost: numeric("estimated_cost", { precision: 10, scale: 4 }).notNull(),
    recordedAt: timestamp("recorded_at", { withTimezone: true }).notNull().default(sql`now()`),
    deletedAt: timestamp("deleted_at", { withTimezone: true }),
  },
  (t) => [
    index("token_costs_tenant_id_idx").on(t.tenantId),
    index("token_costs_execution_id_idx").on(t.executionId),
    tenantIsolationPolicy(t),
    backupReadPolicy(),
  ],
);

export const executionErrors = trace.table.withRLS(
  "execution_errors",
  {
    id: uuid("id").primaryKey(),
    tenantId: uuid("tenant_id")
      .notNull()
      .references(() => tenants.id, { onDelete: "restrict" }),
    executionId: uuid("execution_id")
      .notNull()
      .references(() => executions.id, { onDelete: "restrict" }),
    stepId: uuid("step_id").references(() => executionSteps.id, { onDelete: "restrict" }),
    errorType: text("error_type").notNull(),
    message: text("message").notNull(),
    severity: errorSeverity("severity").notNull(),
    occurredAt: timestamp("occurred_at", { withTimezone: true }).notNull().default(sql`now()`),
    deletedAt: timestamp("deleted_at", { withTimezone: true }),
  },
  (t) => [
    index("execution_errors_tenant_id_idx").on(t.tenantId),
    index("execution_errors_execution_id_idx").on(t.executionId),
    index("execution_errors_severity_idx").on(t.severity),
    tenantIsolationPolicy(t),
    backupReadPolicy(),
  ],
);

export const auditLog = trace.table.withRLS(
  "audit_log",
  {
    id: uuid("id").primaryKey(),
    tenantId: uuid("tenant_id")
      .notNull()
      .references(() => tenants.id, { onDelete: "restrict" }),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "restrict" }),
    action: text("action").notNull(),
    entityType: text("entity_type").notNull(),
    entityId: uuid("entity_id").notNull(),
    details: jsonb("details").notNull().default({}),
    occurredAt: timestamp("occurred_at", { withTimezone: true }).notNull().default(sql`now()`),
  },
  (t) => [
    index("audit_log_tenant_id_occurred_at_idx").on(t.tenantId, t.occurredAt),
    tenantIsolationPolicy(t),
    backupReadPolicy(),
  ],
);
