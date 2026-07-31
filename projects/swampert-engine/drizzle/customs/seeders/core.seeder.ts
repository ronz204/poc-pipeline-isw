import { seed } from "drizzle-seed";
import { eq, sql } from "drizzle-orm";
import { hashSeed, SeededRandom } from "@helpers/random.helper";
import { agents, executions, swarmAgents, swarms, tasks } from "@elements/core.element";

import type { TenantTx } from "@helpers/tenant.helper";

export const TOOLS_CATALOG = [
  "web_search", "code_exec", "file_read", "file_write", "vector_search",
  "sql_query", "http_request", "calendar_lookup", "email_draft", "image_gen",
];

const DEFAULT_AGENT_CONFIG = { temperature: 0.7, maxTokens: 2048 };

const DAY_MS = 24 * 60 * 60 * 1000;

export class CoreSeeder {
  async seedAll(tx: TenantTx, tenant: { id: string }, { seed: seedNumber }: { seed: number }) {
    const tenantSeed = hashSeed(seedNumber, tenant.id);
    const rng = new SeededRandom(tenantSeed);

    const swarmCount = 3 + (tenantSeed % 6); // 3-8
    await seed(tx, { swarms }, { count: swarmCount, seed: tenantSeed }).refine((f) => ({
      swarms: {
        columns: {
          id: f.uuid(),
          tenantId: f.default({ defaultValue: tenant.id }),
          status: f.valuesFromArray({
            values: [
              { weight: 0.6, values: ["active"] },
              { weight: 0.25, values: ["paused"] },
              { weight: 0.15, values: ["archived"] },
            ],
          }),
          deletedAt: f.default({ defaultValue: null }),
        },
      },
    }));

    const agentCount = 5 + (tenantSeed % 11); // 5-15
    await seed(tx, { agents }, { count: agentCount, seed: tenantSeed + 1 }).refine((f) => ({
      agents: {
        columns: {
          id: f.uuid(),
          tenantId: f.default({ defaultValue: tenant.id }),
          tools: f.valuesFromArray({ values: TOOLS_CATALOG, arraySize: 3 }),
          config: f.default({ defaultValue: DEFAULT_AGENT_CONFIG }),
          deletedAt: f.default({ defaultValue: null }),
        },
      },
    }));

    const swarmRows = await tx.select({ id: swarms.id }).from(swarms).where(eq(swarms.tenantId, tenant.id));
    const agentRows = await tx.select({ id: agents.id }).from(agents).where(eq(agents.tenantId, tenant.id));
    const agentIds = agentRows.map((row) => row.id);

    const pairs = swarmRows.flatMap((swarm) =>
      rng.pickSubset(agentIds, 2 + (tenantSeed % 5)).map((agentId) => ({ swarmId: swarm.id, agentId })));
    
    if (pairs.length > 0) await tx.insert(swarmAgents).values(pairs);

    const swarmIds = swarmRows.map((row) => row.id);
    const taskCount = swarmIds.length * 2;
    await seed(tx, { tasks }, { count: taskCount, seed: tenantSeed + 2 }).refine((f) => ({
      tasks: {
        columns: {
          id: f.uuid(),
          tenantId: f.default({ defaultValue: tenant.id }),
          swarmId: f.valuesFromArray({ values: swarmIds }),
          status: f.valuesFromArray({
            values: [
              { weight: 0.3, values: ["pending"] },
              { weight: 0.25, values: ["progress"] },
              { weight: 0.35, values: ["completed"] },
              { weight: 0.1, values: ["failed"] },
            ],
          }),
          priority: f.valuesFromArray({
            values: [
              { weight: 0.5, values: ["medium"] },
              { weight: 0.3, values: ["low"] },
              { weight: 0.2, values: ["high"] },
            ],
          }),
          deletedAt: f.default({ defaultValue: null }),
        },
      },
    }));

    const taskRows = await tx.select({ id: tasks.id }).from(tasks).where(eq(tasks.tenantId, tenant.id));
    const taskIds = taskRows.map((row) => row.id);

    const now = new Date();
    const ninetyDaysAgo = new Date(now.getTime() - 90 * DAY_MS);

    const executionCount = taskIds.length * 2;
    await seed(tx, { executions }, { count: executionCount, seed: tenantSeed + 3 }).refine((f) => ({
      executions: {
        columns: {
          id: f.uuid(),
          tenantId: f.default({ defaultValue: tenant.id }),
          taskId: f.valuesFromArray({ values: taskIds }),
          attemptNumber: f.int({ minValue: 1, maxValue: 3 }),
          status: f.valuesFromArray({
            values: [
              { weight: 0.55, values: ["completed"] },
              { weight: 0.15, values: ["failed"] },
              { weight: 0.15, values: ["running"] },
              { weight: 0.15, values: ["pending"] },
            ],
          }),
          startedAt: f.date({ minDate: ninetyDaysAgo, maxDate: now }),
          deletedAt: f.default({ defaultValue: null }),
        },
      },
    }));

    await tx.execute(sql`
      UPDATE core.executions
      SET finished_at = started_at + make_interval(mins => 5 + (random() * 180)::int)
      WHERE tenant_id = ${tenant.id}
        AND status IN ('completed', 'failed')
        AND finished_at IS NULL
    `);
  };
};
