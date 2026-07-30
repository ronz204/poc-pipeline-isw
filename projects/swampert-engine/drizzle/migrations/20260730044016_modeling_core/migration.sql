CREATE SCHEMA "core";
--> statement-breakpoint
CREATE TYPE "core"."execution_status" AS ENUM('pending', 'running', 'completed', 'failed');

--> statement-breakpoint
CREATE TYPE "core"."swarm_status" AS ENUM('active', 'paused', 'archived');

--> statement-breakpoint
CREATE TYPE "core"."task_priority" AS ENUM('low', 'medium', 'high');

--> statement-breakpoint
CREATE TYPE "core"."task_status" AS ENUM('pending', 'progress', 'completed', 'failed');

--> statement-breakpoint
CREATE TABLE "core"."agents" (
	"id" uuid PRIMARY KEY,
	"tenant_id" uuid NOT NULL,
	"name" text NOT NULL,
	"role" text NOT NULL,
	"base_model" text NOT NULL,
	"tools" text[] DEFAULT '{}'::text[] NOT NULL,
	"config" jsonb DEFAULT '{}' NOT NULL,
	"active" boolean DEFAULT true NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"deleted_at" timestamp with time zone
);

--> statement-breakpoint
ALTER TABLE "core"."agents" ENABLE ROW LEVEL SECURITY;
--> statement-breakpoint
CREATE TABLE "core"."executions" (
	"id" uuid PRIMARY KEY,
	"tenant_id" uuid NOT NULL,
	"task_id" uuid NOT NULL,
	"attempt_number" integer DEFAULT 1 NOT NULL,
	"status" "core"."execution_status" DEFAULT 'pending'::"core"."execution_status" NOT NULL,
	"started_at" timestamp with time zone DEFAULT now() NOT NULL,
	"finished_at" timestamp with time zone,
	"deleted_at" timestamp with time zone
);

--> statement-breakpoint
ALTER TABLE "core"."executions" ENABLE ROW LEVEL SECURITY;
--> statement-breakpoint
CREATE TABLE "core"."swarm_agents" (
	"swarm_id" uuid,
	"agent_id" uuid,
	"added_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "swarm_agents_pkey" PRIMARY KEY("swarm_id","agent_id")
);

--> statement-breakpoint
CREATE TABLE "core"."swarms" (
	"id" uuid PRIMARY KEY,
	"tenant_id" uuid NOT NULL,
	"name" text NOT NULL,
	"description" text,
	"status" "core"."swarm_status" DEFAULT 'active'::"core"."swarm_status" NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"deleted_at" timestamp with time zone
);

--> statement-breakpoint
ALTER TABLE "core"."swarms" ENABLE ROW LEVEL SECURITY;
--> statement-breakpoint
CREATE TABLE "core"."tasks" (
	"id" uuid PRIMARY KEY,
	"tenant_id" uuid NOT NULL,
	"swarm_id" uuid NOT NULL,
	"title" text NOT NULL,
	"description" text,
	"status" "core"."task_status" DEFAULT 'pending'::"core"."task_status" NOT NULL,
	"priority" "core"."task_priority" DEFAULT 'medium'::"core"."task_priority" NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"deleted_at" timestamp with time zone
);

--> statement-breakpoint
ALTER TABLE "core"."tasks" ENABLE ROW LEVEL SECURITY;
--> statement-breakpoint
CREATE INDEX "agents_tenant_id_idx" ON "core"."agents" ("tenant_id");
--> statement-breakpoint
CREATE INDEX "agents_config_gin_idx" ON "core"."agents" USING gin ("config");
--> statement-breakpoint
CREATE INDEX "executions_tenant_id_started_at_idx" ON "core"."executions" ("tenant_id","started_at");
--> statement-breakpoint
CREATE INDEX "executions_task_id_idx" ON "core"."executions" ("task_id");
--> statement-breakpoint
CREATE INDEX "executions_status_idx" ON "core"."executions" ("status");
--> statement-breakpoint
CREATE INDEX "swarms_tenant_id_status_idx" ON "core"."swarms" ("tenant_id","status");
--> statement-breakpoint
CREATE INDEX "tasks_tenant_id_status_idx" ON "core"."tasks" ("tenant_id","status");
--> statement-breakpoint
CREATE INDEX "tasks_swarm_id_idx" ON "core"."tasks" ("swarm_id");
--> statement-breakpoint
ALTER TABLE "core"."agents" ADD CONSTRAINT "agents_tenant_id_tenants_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "auth"."tenants"("id") ON DELETE RESTRICT;
--> statement-breakpoint
ALTER TABLE "core"."executions" ADD CONSTRAINT "executions_tenant_id_tenants_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "auth"."tenants"("id") ON DELETE RESTRICT;
--> statement-breakpoint
ALTER TABLE "core"."executions" ADD CONSTRAINT "executions_task_id_tasks_id_fkey" FOREIGN KEY ("task_id") REFERENCES "core"."tasks"("id") ON DELETE RESTRICT;
--> statement-breakpoint
ALTER TABLE "core"."swarm_agents" ADD CONSTRAINT "swarm_agents_swarm_id_swarms_id_fkey" FOREIGN KEY ("swarm_id") REFERENCES "core"."swarms"("id") ON DELETE RESTRICT;
--> statement-breakpoint
ALTER TABLE "core"."swarm_agents" ADD CONSTRAINT "swarm_agents_agent_id_agents_id_fkey" FOREIGN KEY ("agent_id") REFERENCES "core"."agents"("id") ON DELETE RESTRICT;
--> statement-breakpoint
ALTER TABLE "core"."swarms" ADD CONSTRAINT "swarms_tenant_id_tenants_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "auth"."tenants"("id") ON DELETE RESTRICT;
--> statement-breakpoint
ALTER TABLE "core"."tasks" ADD CONSTRAINT "tasks_tenant_id_tenants_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "auth"."tenants"("id") ON DELETE RESTRICT;
--> statement-breakpoint
ALTER TABLE "core"."tasks" ADD CONSTRAINT "tasks_swarm_id_swarms_id_fkey" FOREIGN KEY ("swarm_id") REFERENCES "core"."swarms"("id") ON DELETE RESTRICT;
--> statement-breakpoint
CREATE POLICY "tenant_isolation" ON "core"."agents" AS PERMISSIVE FOR ALL TO public USING ("core"."agents"."tenant_id" = current_setting('app.current_tenant_id', true)::uuid) WITH CHECK ("core"."agents"."tenant_id" = current_setting('app.current_tenant_id', true)::uuid);
--> statement-breakpoint
CREATE POLICY "backup_read" ON "core"."agents" AS PERMISSIVE FOR SELECT TO "backuper" USING (true);
--> statement-breakpoint
CREATE POLICY "tenant_isolation" ON "core"."executions" AS PERMISSIVE FOR ALL TO public USING ("core"."executions"."tenant_id" = current_setting('app.current_tenant_id', true)::uuid) WITH CHECK ("core"."executions"."tenant_id" = current_setting('app.current_tenant_id', true)::uuid);
--> statement-breakpoint
CREATE POLICY "backup_read" ON "core"."executions" AS PERMISSIVE FOR SELECT TO "backuper" USING (true);
--> statement-breakpoint
CREATE POLICY "tenant_isolation" ON "core"."swarms" AS PERMISSIVE FOR ALL TO public USING ("core"."swarms"."tenant_id" = current_setting('app.current_tenant_id', true)::uuid) WITH CHECK ("core"."swarms"."tenant_id" = current_setting('app.current_tenant_id', true)::uuid);
--> statement-breakpoint
CREATE POLICY "backup_read" ON "core"."swarms" AS PERMISSIVE FOR SELECT TO "backuper" USING (true);
--> statement-breakpoint
CREATE POLICY "tenant_isolation" ON "core"."tasks" AS PERMISSIVE FOR ALL TO public USING ("core"."tasks"."tenant_id" = current_setting('app.current_tenant_id', true)::uuid) WITH CHECK ("core"."tasks"."tenant_id" = current_setting('app.current_tenant_id', true)::uuid);
--> statement-breakpoint
CREATE POLICY "backup_read" ON "core"."tasks" AS PERMISSIVE FOR SELECT TO "backuper" USING (true);
