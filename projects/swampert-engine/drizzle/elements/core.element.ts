import { sql } from "drizzle-orm";
import {
  pgSchema,
  uuid,
  text,
  jsonb,
  integer,
  boolean,
  timestamp,
  index,
  primaryKey,
  pgPolicy,
} from "drizzle-orm/pg-core";
import { backuper } from "./roles.element";
import { tenants } from "./auth.element";

export const core = pgSchema("core");

export const swarmStatus = core.enum("swarm_status", ["active", "paused", "archived"]);
export const taskStatus = core.enum("task_status", ["pending", "progress", "completed", "failed"]);
export const taskPriority = core.enum("task_priority", ["low", "medium", "high"]);
export const executionStatus = core.enum("execution_status", ["pending", "running", "completed", "failed"]);

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

export const swarms = core.table.withRLS(
  "swarms",
  {
    id: uuid("id").primaryKey(),
    tenantId: uuid("tenant_id")
      .notNull()
      .references(() => tenants.id, { onDelete: "restrict" }),
    name: text("name").notNull(),
    description: text("description"),
    status: swarmStatus("status").notNull().default("active"),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().default(sql`now()`),
    deletedAt: timestamp("deleted_at", { withTimezone: true }),
  },
  (t) => [
    index("swarms_tenant_id_status_idx").on(t.tenantId, t.status),
    tenantIsolationPolicy(t),
    backupReadPolicy(),
  ],
);

export const agents = core.table.withRLS(
  "agents",
  {
    id: uuid("id").primaryKey(),
    tenantId: uuid("tenant_id")
      .notNull()
      .references(() => tenants.id, { onDelete: "restrict" }),
    name: text("name").notNull(),
    role: text("role").notNull(),
    baseModel: text("base_model").notNull(),
    tools: text("tools").array().notNull().default([]),
    config: jsonb("config").notNull().default({}),
    active: boolean("active").notNull().default(true),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().default(sql`now()`),
    deletedAt: timestamp("deleted_at", { withTimezone: true }),
  },
  (t) => [
    index("agents_tenant_id_idx").on(t.tenantId),
    index("agents_config_gin_idx").using("gin", t.config),
    tenantIsolationPolicy(t),
    backupReadPolicy(),
  ],
);

export const swarmAgents = core.table(
  "swarm_agents",
  {
    swarmId: uuid("swarm_id")
      .notNull()
      .references(() => swarms.id, { onDelete: "restrict" }),
    agentId: uuid("agent_id")
      .notNull()
      .references(() => agents.id, { onDelete: "restrict" }),
    addedAt: timestamp("added_at", { withTimezone: true }).notNull().default(sql`now()`),
  },
  (t) => [primaryKey({ columns: [t.swarmId, t.agentId] })],
);

export const tasks = core.table.withRLS(
  "tasks",
  {
    id: uuid("id").primaryKey(),
    tenantId: uuid("tenant_id")
      .notNull()
      .references(() => tenants.id, { onDelete: "restrict" }),
    swarmId: uuid("swarm_id")
      .notNull()
      .references(() => swarms.id, { onDelete: "restrict" }),
    title: text("title").notNull(),
    description: text("description"),
    status: taskStatus("status").notNull().default("pending"),
    priority: taskPriority("priority").notNull().default("medium"),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().default(sql`now()`),
    deletedAt: timestamp("deleted_at", { withTimezone: true }),
  },
  (t) => [
    index("tasks_tenant_id_status_idx").on(t.tenantId, t.status),
    index("tasks_swarm_id_idx").on(t.swarmId),
    tenantIsolationPolicy(t),
    backupReadPolicy(),
  ],
);

export const executions = core.table.withRLS(
  "executions",
  {
    id: uuid("id").primaryKey(),
    tenantId: uuid("tenant_id")
      .notNull()
      .references(() => tenants.id, { onDelete: "restrict" }),
    taskId: uuid("task_id")
      .notNull()
      .references(() => tasks.id, { onDelete: "restrict" }),
    attemptNumber: integer("attempt_number").notNull().default(1),
    status: executionStatus("status").notNull().default("pending"),
    startedAt: timestamp("started_at", { withTimezone: true }).notNull().default(sql`now()`),
    finishedAt: timestamp("finished_at", { withTimezone: true }),
    deletedAt: timestamp("deleted_at", { withTimezone: true }),
  },
  (t) => [
    index("executions_tenant_id_started_at_idx").on(t.tenantId, t.startedAt),
    index("executions_task_id_idx").on(t.taskId),
    index("executions_status_idx").on(t.status),
    tenantIsolationPolicy(t),
    backupReadPolicy(),
  ],
);
