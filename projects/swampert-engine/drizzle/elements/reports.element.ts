import { tenants } from "@elements/auth.element";
import { columns } from "@customs/helpers/column.helper";
import { swarms, taskStatus } from "@elements/core.element";
import { errorSeverity } from "@elements/trace.element";
import { policies } from "@customs/helpers/policies.helper";

import {
  pgSchema, uuid, date, integer, numeric, primaryKey,
} from "drizzle-orm/pg-core";

export const reports = pgSchema("reports");

export const monthlyExecutionSummary = reports.table.withRLS("monthly_execution_summary",
  {
    tenantId: columns.tenantId(() => tenants.id),
    period: date("period").notNull(),
    executionCount: integer("execution_count").notNull(),
    avgDurationSeconds: numeric("avg_duration_seconds", { precision: 10, scale: 2 }),
    totalCost: numeric("total_cost", { precision: 12, scale: 4 }).notNull(),
    refreshedAt: columns.requiredTimestamp("refreshed_at"),
  }, (t) => [
    primaryKey({ columns: [t.tenantId, t.period] }),
    policies.tenantIsolationPolicy(t.tenantId),
    policies.backupReadablePolicy(),
  ]);

export const swarmTaskSummary = reports.table.withRLS("swarm_task_summary",
  {
    tenantId: columns.tenantId(() => tenants.id),
    swarmId: uuid("swarm_id").notNull()
      .references(() => swarms.id, { onDelete: "restrict" }),
    taskStatus: taskStatus("task_status").notNull(),
    taskCount: integer("task_count").notNull(),
    refreshedAt: columns.requiredTimestamp("refreshed_at"),
  }, (t) => [
    primaryKey({ columns: [t.tenantId, t.swarmId, t.taskStatus] }),
    policies.tenantIsolationPolicy(t.tenantId),
    policies.backupReadablePolicy(),
  ]);

export const errorSummary = reports.table.withRLS("error_summary",
  {
    tenantId: columns.tenantId(() => tenants.id),
    period: date("period").notNull(),
    severity: errorSeverity("severity").notNull(),
    errorCount: integer("error_count").notNull(),
    refreshedAt: columns.requiredTimestamp("refreshed_at"),
  }, (t) => [
    primaryKey({ columns: [t.tenantId, t.period, t.severity] }),
    policies.tenantIsolationPolicy(t.tenantId),
    policies.backupReadablePolicy(),
  ]);
