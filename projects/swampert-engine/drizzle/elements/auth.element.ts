import { columns } from "@customs/helpers/column.helper";
import { policies } from "@customs/helpers/policies.helper";
import { pgSchema, uuid, text, boolean, unique } from "drizzle-orm/pg-core";

export const auth = pgSchema("auth");

export const tenantPlan = auth.enum("tenant_plan", ["basic", "pro", "enterprise"]);
export const userRole = auth.enum("user_role", ["admin", "member", "viewer"]);

export const tenants = auth.table("tenants",
  {
    id: uuid("id").primaryKey(),
    name: text("name").notNull(),
    slug: text("slug").notNull().unique(),
    plan: tenantPlan("plan").notNull(),
    active: boolean("active").notNull().default(true),
    createdAt: columns.requiredTimestamp("created_at"),
    deletedAt: columns.optionalTimestamp("deleted_at"),
  });

export const users = auth.table.withRLS("users",
  {
    id: uuid("id").primaryKey(),
    tenantId: columns.tenantId(() => tenants.id),
    name: text("name").notNull(),
    email: text("email").notNull(),
    password: text("password").notNull(),
    role: userRole("role").notNull(),
    active: boolean("active").notNull().default(true),
    createdAt: columns.requiredTimestamp("created_at"),
    deletedAt: columns.optionalTimestamp("deleted_at"),
  }, (t) => [
    unique("users_tenant_id_email_unique").on(t.tenantId, t.email),
    policies.tenantIsolationPolicy(t.tenantId),
    policies.backupReadablePolicy(),
  ]);
