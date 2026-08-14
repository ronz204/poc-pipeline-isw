CREATE SCHEMA "reports";
--> statement-breakpoint
CREATE TABLE "reports"."error_summary" (
	"tenant_id" uuid,
	"period" date,
	"severity" "trace"."error_severity",
	"error_count" integer NOT NULL,
	"refreshed_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "error_summary_pkey" PRIMARY KEY("tenant_id","period","severity")
);
--> statement-breakpoint
ALTER TABLE "reports"."error_summary" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
CREATE TABLE "reports"."monthly_execution_summary" (
	"tenant_id" uuid,
	"period" date,
	"execution_count" integer NOT NULL,
	"avg_duration_seconds" numeric(10,2),
	"total_cost" numeric(12,4) NOT NULL,
	"refreshed_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "monthly_execution_summary_pkey" PRIMARY KEY("tenant_id","period")
);
--> statement-breakpoint
ALTER TABLE "reports"."monthly_execution_summary" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
CREATE TABLE "reports"."swarm_task_summary" (
	"tenant_id" uuid,
	"swarm_id" uuid,
	"task_status" "core"."task_status",
	"task_count" integer NOT NULL,
	"refreshed_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "swarm_task_summary_pkey" PRIMARY KEY("tenant_id","swarm_id","task_status")
);
--> statement-breakpoint
ALTER TABLE "reports"."swarm_task_summary" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
ALTER TABLE "reports"."error_summary" ADD CONSTRAINT "error_summary_tenant_id_tenants_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "auth"."tenants"("id") ON DELETE RESTRICT;--> statement-breakpoint
ALTER TABLE "reports"."monthly_execution_summary" ADD CONSTRAINT "monthly_execution_summary_tenant_id_tenants_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "auth"."tenants"("id") ON DELETE RESTRICT;--> statement-breakpoint
ALTER TABLE "reports"."swarm_task_summary" ADD CONSTRAINT "swarm_task_summary_tenant_id_tenants_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "auth"."tenants"("id") ON DELETE RESTRICT;--> statement-breakpoint
ALTER TABLE "reports"."swarm_task_summary" ADD CONSTRAINT "swarm_task_summary_swarm_id_swarms_id_fkey" FOREIGN KEY ("swarm_id") REFERENCES "core"."swarms"("id") ON DELETE RESTRICT;--> statement-breakpoint
CREATE POLICY "tenant_isolation" ON "reports"."error_summary" AS PERMISSIVE FOR ALL TO public USING ("reports"."error_summary"."tenant_id" = current_setting('app.current_tenant_id', true)::uuid) WITH CHECK ("reports"."error_summary"."tenant_id" = current_setting('app.current_tenant_id', true)::uuid);--> statement-breakpoint
CREATE POLICY "backup_read" ON "reports"."error_summary" AS PERMISSIVE FOR SELECT TO "backuper" USING (true);--> statement-breakpoint
CREATE POLICY "tenant_isolation" ON "reports"."monthly_execution_summary" AS PERMISSIVE FOR ALL TO public USING ("reports"."monthly_execution_summary"."tenant_id" = current_setting('app.current_tenant_id', true)::uuid) WITH CHECK ("reports"."monthly_execution_summary"."tenant_id" = current_setting('app.current_tenant_id', true)::uuid);--> statement-breakpoint
CREATE POLICY "backup_read" ON "reports"."monthly_execution_summary" AS PERMISSIVE FOR SELECT TO "backuper" USING (true);--> statement-breakpoint
CREATE POLICY "tenant_isolation" ON "reports"."swarm_task_summary" AS PERMISSIVE FOR ALL TO public USING ("reports"."swarm_task_summary"."tenant_id" = current_setting('app.current_tenant_id', true)::uuid) WITH CHECK ("reports"."swarm_task_summary"."tenant_id" = current_setting('app.current_tenant_id', true)::uuid);--> statement-breakpoint
CREATE POLICY "backup_read" ON "reports"."swarm_task_summary" AS PERMISSIVE FOR SELECT TO "backuper" USING (true);