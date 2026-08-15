import { eq, inArray } from "drizzle-orm";
import { seed } from "drizzle-seed";
import { generateId } from "@database/drizzler.client";
import { hashSeed, SeededRandom } from "@helpers/random.helper";
import { agents, executions } from "@elements/core.element";
import { TOOLS_CATALOG } from "@customs/seeders/core.seeder";
import { executionErrors, executionSteps, tokenCosts } from "@elements/trace.element";

import type { TenantTx } from "@helpers/tenant.helper";

const ERROR_TYPES = [
  "timeout", "rate_limit", "invalid_output", "tool_failure", "context_overflow",
];

const ERROR_SEVERITY_POOL = [
  ...Array(8).fill("low" as const),
  ...Array(7).fill("medium" as const),
  ...Array(4).fill("high" as const),
  ...Array(1).fill("critical" as const),
]; // 40% low, 35% medium, 20% high, 5% critical

const ERROR_OFFSET_MINUTES_POOL = Array.from({ length: 30 }, (_, i) => i + 1); // 1-30min after the execution finished

export class TraceSeeder {
  async seedAll(tx: TenantTx, tenant: { id: string }, { seed: seedNumber }: { seed: number }) {
    const tenantSeed = hashSeed(seedNumber, tenant.id);
    const executionRows = await tx
      .select({ id: executions.id, status: executions.status })
      .from(executions).where(eq(executions.tenantId, tenant.id));

    const ranExecutionIds = executionRows.filter((row) => row.status !== "pending").map((row) => row.id);
    const failedExecutionIds = executionRows.filter((row) => row.status === "failed").map((row) => row.id);

    const agentRows = await tx.select({ id: agents.id }).from(agents).where(eq(agents.tenantId, tenant.id));
    const agentIds = agentRows.map((row) => row.id);

    if (ranExecutionIds.length > 0 && agentIds.length > 0) {
      await seed(tx, { executionSteps }, { count: ranExecutionIds.length * 3, seed: tenantSeed }).refine((f) => ({
        executionSteps: {
          columns: {
            id: f.uuid(),
            tenantId: f.default({ defaultValue: tenant.id }),
            executionId: f.valuesFromArray({ values: ranExecutionIds }),
            agentId: f.valuesFromArray({ values: agentIds }),
            stepNumber: f.int({ minValue: 1, maxValue: 6 }),
            toolsUsed: f.valuesFromArray({ values: TOOLS_CATALOG, arraySize: 2 }),
            deletedAt: f.default({ defaultValue: null }),
          },
        },
      }));

      await seed(tx, { tokenCosts }, { count: Math.ceil(ranExecutionIds.length * 1.5), seed: tenantSeed + 1 }).refine((f) => ({
        tokenCosts: {
          columns: {
            id: f.uuid(),
            tenantId: f.default({ defaultValue: tenant.id }),
            executionId: f.valuesFromArray({ values: ranExecutionIds }),
            stepId: f.default({ defaultValue: null }),
            inputTokens: f.int({ minValue: 50, maxValue: 4000 }),
            outputTokens: f.int({ minValue: 20, maxValue: 2000 }),
            estimatedCost: f.number({ minValue: 0.001, maxValue: 2, precision: 1000 }),
            deletedAt: f.default({ defaultValue: null }),
          },
        },
      }));
    }

    if (failedExecutionIds.length > 0) {
      // Hand-built, not drizzle-seed: reports.sp_refresh_reports buckets error_summary
      // by execution_errors.occurred_at directly (unlike monthly_execution_summary,
      // which filters on the EXECUTION's started_at instead) — occurredAt has to
      // correlate with the failed execution it belongs to, which drizzle-seed's
      // per-column generators can't do (same reasoning as core.seeder.ts's hand-built
      // executionRows: correlated columns need a real join, not independent generators).
      const rng = new SeededRandom(tenantSeed + 2);

      const failedExecutionRows = await tx
        .select({ id: executions.id, finishedAt: executions.finishedAt })
        .from(executions)
        .where(inArray(executions.id, failedExecutionIds));

      const errorRows = failedExecutionRows
        .filter((row) => row.finishedAt !== null)
        .map((row) => {
          const errorType = rng.pick(ERROR_TYPES);

          return {
            id: generateId(),
            tenantId: tenant.id,
            executionId: row.id,
            stepId: null,
            errorType,
            message: `${errorType} on execution ${row.id}`,
            severity: rng.pick(ERROR_SEVERITY_POOL),
            occurredAt: new Date(row.finishedAt!.getTime() + rng.pick(ERROR_OFFSET_MINUTES_POOL) * 60_000),
            deletedAt: null,
          };
        });

      if (errorRows.length > 0) await tx.insert(executionErrors).values(errorRows);
    }
  }
}
