CREATE SCHEMA "trace";
--> statement-breakpoint
CREATE TYPE "trace"."error_severity" AS ENUM('low', 'medium', 'high', 'critical');

--> statement-breakpoint
CREATE TABLE "trace"."audit_log" (
	"id" uuid PRIMARY KEY,
	"tenant_id" uuid NOT NULL,
	"user_id" uuid NOT NULL,
	"action" text NOT NULL,
	"entity_type" text NOT NULL,
	"entity_id" uuid NOT NULL,
	"details" jsonb DEFAULT '{}' NOT NULL,
	"occurred_at" timestamp with time zone DEFAULT now() NOT NULL
);

--> statement-breakpoint
ALTER TABLE "trace"."audit_log" ENABLE ROW LEVEL SECURITY;
--> statement-breakpoint
CREATE TABLE "trace"."execution_errors" (
	"id" uuid PRIMARY KEY,
	"tenant_id" uuid NOT NULL,
	"execution_id" uuid NOT NULL,
	"step_id" uuid,
	"error_type" text NOT NULL,
	"message" text NOT NULL,
	"severity" "trace"."error_severity" NOT NULL,
	"occurred_at" timestamp with time zone DEFAULT now() NOT NULL,
	"deleted_at" timestamp with time zone
);

--> statement-breakpoint
ALTER TABLE "trace"."execution_errors" ENABLE ROW LEVEL SECURITY;
--> statement-breakpoint
CREATE TABLE "trace"."execution_steps" (
	"id" uuid PRIMARY KEY,
	"tenant_id" uuid NOT NULL,
	"execution_id" uuid NOT NULL,
	"agent_id" uuid NOT NULL,
	"step_number" integer NOT NULL,
	"reasoning" jsonb DEFAULT '{}' NOT NULL,
	"tools_used" text[] DEFAULT '{}'::text[] NOT NULL,
	"occurred_at" timestamp with time zone DEFAULT now() NOT NULL,
	"deleted_at" timestamp with time zone
);

--> statement-breakpoint
ALTER TABLE "trace"."execution_steps" ENABLE ROW LEVEL SECURITY;
--> statement-breakpoint
CREATE TABLE "trace"."token_costs" (
	"id" uuid PRIMARY KEY,
	"tenant_id" uuid NOT NULL,
	"execution_id" uuid NOT NULL,
	"step_id" uuid,
	"input_tokens" integer NOT NULL,
	"output_tokens" integer NOT NULL,
	"estimated_cost" numeric(10,4) NOT NULL,
	"recorded_at" timestamp with time zone DEFAULT now() NOT NULL,
	"deleted_at" timestamp with time zone
);

--> statement-breakpoint
ALTER TABLE "trace"."token_costs" ENABLE ROW LEVEL SECURITY;
--> statement-breakpoint
CREATE INDEX "audit_log_tenant_id_occurred_at_idx" ON "trace"."audit_log" ("tenant_id","occurred_at");
--> statement-breakpoint
CREATE INDEX "execution_errors_tenant_id_idx" ON "trace"."execution_errors" ("tenant_id");
--> statement-breakpoint
CREATE INDEX "execution_errors_execution_id_idx" ON "trace"."execution_errors" ("execution_id");
--> statement-breakpoint
CREATE INDEX "execution_errors_severity_idx" ON "trace"."execution_errors" ("severity");
--> statement-breakpoint
CREATE INDEX "execution_steps_tenant_id_idx" ON "trace"."execution_steps" ("tenant_id");
--> statement-breakpoint
CREATE INDEX "execution_steps_execution_id_step_number_idx" ON "trace"."execution_steps" ("execution_id","step_number");
--> statement-breakpoint
CREATE INDEX "execution_steps_reasoning_gin_idx" ON "trace"."execution_steps" USING gin ("reasoning");
--> statement-breakpoint
CREATE INDEX "token_costs_tenant_id_idx" ON "trace"."token_costs" ("tenant_id");
--> statement-breakpoint
CREATE INDEX "token_costs_execution_id_idx" ON "trace"."token_costs" ("execution_id");
--> statement-breakpoint
ALTER TABLE "trace"."audit_log" ADD CONSTRAINT "audit_log_tenant_id_tenants_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "auth"."tenants"("id") ON DELETE RESTRICT;
--> statement-breakpoint
ALTER TABLE "trace"."audit_log" ADD CONSTRAINT "audit_log_user_id_users_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE RESTRICT;
--> statement-breakpoint
ALTER TABLE "trace"."execution_errors" ADD CONSTRAINT "execution_errors_tenant_id_tenants_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "auth"."tenants"("id") ON DELETE RESTRICT;
--> statement-breakpoint
ALTER TABLE "trace"."execution_errors" ADD CONSTRAINT "execution_errors_execution_id_executions_id_fkey" FOREIGN KEY ("execution_id") REFERENCES "core"."executions"("id") ON DELETE RESTRICT;
--> statement-breakpoint
ALTER TABLE "trace"."execution_errors" ADD CONSTRAINT "execution_errors_step_id_execution_steps_id_fkey" FOREIGN KEY ("step_id") REFERENCES "trace"."execution_steps"("id") ON DELETE RESTRICT;
--> statement-breakpoint
ALTER TABLE "trace"."execution_steps" ADD CONSTRAINT "execution_steps_tenant_id_tenants_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "auth"."tenants"("id") ON DELETE RESTRICT;
--> statement-breakpoint
ALTER TABLE "trace"."execution_steps" ADD CONSTRAINT "execution_steps_execution_id_executions_id_fkey" FOREIGN KEY ("execution_id") REFERENCES "core"."executions"("id") ON DELETE RESTRICT;
--> statement-breakpoint
ALTER TABLE "trace"."execution_steps" ADD CONSTRAINT "execution_steps_agent_id_agents_id_fkey" FOREIGN KEY ("agent_id") REFERENCES "core"."agents"("id") ON DELETE RESTRICT;
--> statement-breakpoint
ALTER TABLE "trace"."token_costs" ADD CONSTRAINT "token_costs_tenant_id_tenants_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "auth"."tenants"("id") ON DELETE RESTRICT;
--> statement-breakpoint
ALTER TABLE "trace"."token_costs" ADD CONSTRAINT "token_costs_execution_id_executions_id_fkey" FOREIGN KEY ("execution_id") REFERENCES "core"."executions"("id") ON DELETE RESTRICT;
--> statement-breakpoint
ALTER TABLE "trace"."token_costs" ADD CONSTRAINT "token_costs_step_id_execution_steps_id_fkey" FOREIGN KEY ("step_id") REFERENCES "trace"."execution_steps"("id") ON DELETE RESTRICT;
--> statement-breakpoint
CREATE POLICY "tenant_isolation" ON "trace"."audit_log" AS PERMISSIVE FOR ALL TO public USING ("trace"."audit_log"."tenant_id" = current_setting('app.current_tenant_id', true)::uuid) WITH CHECK ("trace"."audit_log"."tenant_id" = current_setting('app.current_tenant_id', true)::uuid);
--> statement-breakpoint
CREATE POLICY "backup_read" ON "trace"."audit_log" AS PERMISSIVE FOR SELECT TO "backuper" USING (true);
--> statement-breakpoint
CREATE POLICY "tenant_isolation" ON "trace"."execution_errors" AS PERMISSIVE FOR ALL TO public USING ("trace"."execution_errors"."tenant_id" = current_setting('app.current_tenant_id', true)::uuid) WITH CHECK ("trace"."execution_errors"."tenant_id" = current_setting('app.current_tenant_id', true)::uuid);
--> statement-breakpoint
CREATE POLICY "backup_read" ON "trace"."execution_errors" AS PERMISSIVE FOR SELECT TO "backuper" USING (true);
--> statement-breakpoint
CREATE POLICY "tenant_isolation" ON "trace"."execution_steps" AS PERMISSIVE FOR ALL TO public USING ("trace"."execution_steps"."tenant_id" = current_setting('app.current_tenant_id', true)::uuid) WITH CHECK ("trace"."execution_steps"."tenant_id" = current_setting('app.current_tenant_id', true)::uuid);
--> statement-breakpoint
CREATE POLICY "backup_read" ON "trace"."execution_steps" AS PERMISSIVE FOR SELECT TO "backuper" USING (true);
--> statement-breakpoint
CREATE POLICY "tenant_isolation" ON "trace"."token_costs" AS PERMISSIVE FOR ALL TO public USING ("trace"."token_costs"."tenant_id" = current_setting('app.current_tenant_id', true)::uuid) WITH CHECK ("trace"."token_costs"."tenant_id" = current_setting('app.current_tenant_id', true)::uuid);
--> statement-breakpoint
CREATE POLICY "backup_read" ON "trace"."token_costs" AS PERMISSIVE FOR SELECT TO "backuper" USING (true);
