import { tenants } from "@elements/auth.element";
import { columns } from "@customs/helpers/column.helper";
import { policies } from "@customs/helpers/policies.helper";

import {
  pgSchema, uuid, text, jsonb, integer,
  boolean, index, primaryKey,
} from "drizzle-orm/pg-core";

export const core = pgSchema("core");

export const taskPriority = core.enum("task_priority", ["low", "medium", "high"]);
export const swarmStatus = core.enum("swarm_status", ["active", "paused", "archived"]);
export const taskStatus = core.enum("task_status", ["pending", "progress", "completed", "failed"]);
export const executionStatus = core.enum("execution_status", ["pending", "running", "completed", "failed"]);

export const swarms = core.table.withRLS("swarms",
  {
    id: uuid("id").primaryKey(),
    tenantId: columns.tenantId(() => tenants.id),
    name: text("name").notNull(),
    description: text("description"),
    status: swarmStatus("status").notNull().default("active"),
    createdAt: columns.requiredTimestamp("created_at"),
    deletedAt: columns.optionalTimestamp("deleted_at"),
  }, (t) => [
    index("swarms_tenant_id_status_idx").on(t.tenantId, t.status),
    policies.tenantIsolationPolicy(t.tenantId),
    policies.backupReadablePolicy(),
  ]);

export const agents = core.table.withRLS("agents",
  {
    id: uuid("id").primaryKey(),
    tenantId: columns.tenantId(() => tenants.id),
    name: text("name").notNull(),
    role: text("role").notNull(),
    baseModel: text("base_model").notNull(),
    tools: text("tools").array().notNull().default([]),
    config: jsonb("config").notNull().default({}),
    active: boolean("active").notNull().default(true),
    createdAt: columns.requiredTimestamp("created_at"),
    deletedAt: columns.optionalTimestamp("deleted_at"),
  }, (t) => [
    index("agents_tenant_id_idx").on(t.tenantId),
    index("agents_config_gin_idx").using("gin", t.config),
    policies.tenantIsolationPolicy(t.tenantId),
    policies.backupReadablePolicy(),
  ]);

export const swarmAgents = core.table("swarm_agents",
  {
    swarmId: uuid("swarm_id").notNull().references(() => swarms.id, { onDelete: "restrict" }),
    agentId: uuid("agent_id").notNull().references(() => agents.id, { onDelete: "restrict" }),
    addedAt: columns.requiredTimestamp("added_at"),
  }, (t) => [
    primaryKey({ columns: [t.swarmId, t.agentId] }),
  ]);

export const tasks = core.table.withRLS("tasks",
  {
    id: uuid("id").primaryKey(),
    tenantId: columns.tenantId(() => tenants.id),
    swarmId: uuid("swarm_id").notNull()
      .references(() => swarms.id, { onDelete: "restrict" }),
    title: text("title").notNull(),
    description: text("description"),
    status: taskStatus("status").notNull().default("pending"),
    priority: taskPriority("priority").notNull().default("medium"),
    createdAt: columns.requiredTimestamp("created_at"),
    deletedAt: columns.optionalTimestamp("deleted_at"),
  }, (t) => [
    index("tasks_tenant_id_status_idx").on(t.tenantId, t.status),
    index("tasks_swarm_id_idx").on(t.swarmId),
    policies.tenantIsolationPolicy(t.tenantId),
    policies.backupReadablePolicy(),
  ]);

export const executions = core.table.withRLS("executions",
  {
    id: uuid("id").primaryKey(),
    tenantId: columns.tenantId(() => tenants.id),
    taskId: uuid("task_id").notNull()
      .references(() => tasks.id, { onDelete: "restrict" }),
    attemptNumber: integer("attempt_number").notNull().default(1),
    status: executionStatus("status").notNull().default("pending"),
    startedAt: columns.requiredTimestamp("started_at"),
    finishedAt: columns.optionalTimestamp("finished_at"),
    deletedAt: columns.optionalTimestamp("deleted_at"),
  }, (t) => [
    index("executions_tenant_id_started_at_idx").on(t.tenantId, t.startedAt),
    index("executions_task_id_idx").on(t.taskId),
    index("executions_status_idx").on(t.status),
    policies.tenantIsolationPolicy(t.tenantId),
    policies.backupReadablePolicy(),
  ]);
