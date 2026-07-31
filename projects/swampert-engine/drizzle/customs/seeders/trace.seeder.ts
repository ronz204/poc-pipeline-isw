import { eq } from "drizzle-orm";
import { seed } from "drizzle-seed";
import { hashSeed } from "@helpers/random.helper";
import { agents, executions } from "@elements/core.element";
import { TOOLS_CATALOG } from "@customs/seeders/core.seeder";
import { executionErrors, executionSteps, tokenCosts } from "@elements/trace.element";

import type { TenantTx } from "@helpers/tenant.helper";

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
      await seed(tx, { executionErrors }, { count: failedExecutionIds.length, seed: tenantSeed + 2 }).refine((f) => ({
        executionErrors: {
          columns: {
            id: f.uuid(),
            tenantId: f.default({ defaultValue: tenant.id }),
            executionId: f.valuesFromArray({ values: failedExecutionIds, isUnique: true }),
            stepId: f.default({ defaultValue: null }),
            severity: f.valuesFromArray({
              values: [
                { weight: 0.4, values: ["low"] },
                { weight: 0.35, values: ["medium"] },
                { weight: 0.2, values: ["high"] },
                { weight: 0.05, values: ["critical"] },
              ],
            }),
            deletedAt: f.default({ defaultValue: null }),
          },
        },
      }));
    }
  }
}
