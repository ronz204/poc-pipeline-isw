import { sql } from "drizzle-orm";
import { backuper } from "./roles.element";
import { pgSchema, pgPolicy } from "drizzle-orm/pg-core";
import { uuid, text, boolean, timestamp, unique } from "drizzle-orm/pg-core";

export const auth = pgSchema("auth");

export const tenantPlan = auth.enum("tenant_plan", ["basic", "pro", "enterprise"]);
export const userRole = auth.enum("user_role", ["admin", "member", "viewer"]);

export const tenants = auth.table("tenants", {
  id: uuid("id").primaryKey(),
  name: text("name").notNull(),
  slug: text("slug").notNull().unique(),
  plan: tenantPlan("plan").notNull(),
  active: boolean("active").notNull().default(true),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().default(sql`now()`),
  deletedAt: timestamp("deleted_at", { withTimezone: true }),
});

export const users = auth.table.withRLS("users",
  {
    id: uuid("id").primaryKey(),
    tenantId: uuid("tenant_id").notNull()
      .references(() => tenants.id, { onDelete: "restrict" }),
    name: text("name").notNull(),
    email: text("email").notNull(),
    passwordHash: text("password_hash").notNull(),
    role: userRole("role").notNull(),
    active: boolean("active").notNull().default(true),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().default(sql`now()`),
    deletedAt: timestamp("deleted_at", { withTimezone: true }),
  },
  (t) => [
    unique("users_tenant_id_email_unique").on(t.tenantId, t.email),
    pgPolicy("tenant_isolation", {
      as: "permissive",
      for: "all",
      using: sql`${t.tenantId} = current_setting('app.current_tenant_id', true)::uuid`,
      withCheck: sql`${t.tenantId} = current_setting('app.current_tenant_id', true)::uuid`,
    }),
    pgPolicy("backup_read", {
      as: "permissive",
      for: "select",
      to: backuper,
      using: sql`true`,
    }),
  ],
);
