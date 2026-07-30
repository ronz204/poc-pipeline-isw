CREATE SCHEMA "auth";
--> statement-breakpoint
CREATE TYPE "auth"."tenant_plan" AS ENUM('basic', 'pro', 'enterprise');--> statement-breakpoint
CREATE TYPE "auth"."user_role" AS ENUM('admin', 'member', 'viewer');--> statement-breakpoint
CREATE TABLE "auth"."tenants" (
	"id" uuid PRIMARY KEY,
	"name" text NOT NULL,
	"slug" text NOT NULL UNIQUE,
	"plan" "auth"."tenant_plan" NOT NULL,
	"active" boolean DEFAULT true NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"deleted_at" timestamp with time zone
);
--> statement-breakpoint
CREATE TABLE "auth"."users" (
	"id" uuid PRIMARY KEY,
	"tenant_id" uuid NOT NULL,
	"name" text NOT NULL,
	"email" text NOT NULL,
	"password" text NOT NULL,
	"role" "auth"."user_role" NOT NULL,
	"active" boolean DEFAULT true NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"deleted_at" timestamp with time zone,
	CONSTRAINT "users_tenant_id_email_unique" UNIQUE("tenant_id","email")
);
--> statement-breakpoint
ALTER TABLE "auth"."users" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
ALTER TABLE "auth"."users" ADD CONSTRAINT "users_tenant_id_tenants_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "auth"."tenants"("id") ON DELETE RESTRICT;--> statement-breakpoint
CREATE POLICY "tenant_isolation" ON "auth"."users" AS PERMISSIVE FOR ALL TO public USING ("auth"."users"."tenant_id" = current_setting('app.current_tenant_id', true)::uuid) WITH CHECK ("auth"."users"."tenant_id" = current_setting('app.current_tenant_id', true)::uuid);--> statement-breakpoint
CREATE POLICY "backup_read" ON "auth"."users" AS PERMISSIVE FOR SELECT TO "backuper" USING (true);