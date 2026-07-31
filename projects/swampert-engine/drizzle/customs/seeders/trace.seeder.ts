import { eq } from "drizzle-orm";
import { seed } from "drizzle-seed";
import { users } from "@elements/auth.element";
import { generateId } from "@database/drizzler.client";
import { TOOLS_CATALOG } from "@customs/seeders/core.seeder";
import { hashSeed, SeededRandom } from "@helpers/random.helper";
import { agents, executions, swarms, tasks } from "@elements/core.element";
import { auditLog, executionErrors, executionSteps, tokenCosts } from "@elements/trace.element";

import type { TenantTx } from "@helpers/tenant.helper";

const AUDIT_ACTIONS = ["created", "updated", "archived"] as const;

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

    await this.seedAuditLog(tx, tenant);
  }

  private async seedAuditLog(tx: TenantTx, tenant: { id: string }) {
    const userRows = await tx.select({ id: users.id }).from(users).where(eq(users.tenantId, tenant.id));
    const swarmRows = await tx.select({ id: swarms.id }).from(swarms).where(eq(swarms.tenantId, tenant.id));
    const agentRows = await tx.select({ id: agents.id }).from(agents).where(eq(agents.tenantId, tenant.id));
    const taskRows = await tx.select({ id: tasks.id }).from(tasks).where(eq(tasks.tenantId, tenant.id));

    const entities = [
      ...swarmRows.map((row) => ({ entityType: "swarm" as const, entityId: row.id })),
      ...agentRows.map((row) => ({ entityType: "agent" as const, entityId: row.id })),
      ...taskRows.map((row) => ({ entityType: "task" as const, entityId: row.id })),
    ];

    if (userRows.length === 0 || entities.length === 0) return;

    const rng = new SeededRandom(userRows.length + entities.length);
    const rows = userRows.flatMap((user) =>
      Array.from({ length: 3 }, () => {
        const entity = rng.pick(entities);
        return {
          id: generateId(),
          tenantId: tenant.id,
          userId: user.id,
          action: rng.pick(AUDIT_ACTIONS),
          entityType: entity.entityType,
          entityId: entity.entityId,
        };
      }),
    );

    await tx.insert(auditLog).values(rows);
  };
};
