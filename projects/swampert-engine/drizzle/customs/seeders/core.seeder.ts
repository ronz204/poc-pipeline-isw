import { eq } from "drizzle-orm";
import { seed } from "drizzle-seed";
import { generateId } from "@database/drizzler.client";
import { hashSeed, SeededRandom } from "@helpers/random.helper";
import { agents, executions, swarmAgents, swarms, tasks } from "@elements/core.element";

import type { TenantTx } from "@helpers/tenant.helper";

export const TOOLS_CATALOG = [
  "web_search", "code_exec", "file_read", "file_write", "vector_search",
  "sql_query", "http_request", "calendar_lookup", "email_draft", "image_gen",
];

const DEFAULT_AGENT_CONFIG = { temperature: 0.7, maxTokens: 2048 };

const DAY_MS = 24 * 60 * 60 * 1000;

const EXECUTION_STATUS_POOL = [
  ...Array(11).fill("completed" as const),
  ...Array(3).fill("failed" as const),
  ...Array(3).fill("running" as const),
  ...Array(3).fill("pending" as const),
]; // pesos aproximados: 55% completed, 15% failed, 15% running, 15% pending

const ATTEMPT_COUNT_POOL = [1, 2, 2, 2, 3]; // promedio ~2 intentos por tarea
const START_GAP_MINUTES_POOL = Array.from({ length: 24 }, (_, i) => (i + 1) * 60); // 1-24h entre reintentos
const DURATION_MINUTES_POOL = Array.from({ length: 36 }, (_, i) => 5 + i * 5); // 5-180min de duración

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

    const swarmRows = await tx.select({ id: swarms.id, status: swarms.status }).from(swarms).where(eq(swarms.tenantId, tenant.id));
    const agentRows = await tx.select({ id: agents.id }).from(agents).where(eq(agents.tenantId, tenant.id));
    const agentIds = agentRows.map((row) => row.id);

    const pairs = swarmRows.flatMap((swarm) =>
      rng.pickSubset(agentIds, 2 + (tenantSeed % 5)).map((agentId) => ({ swarmId: swarm.id, agentId })));
    
    if (pairs.length > 0) await tx.insert(swarmAgents).values(pairs);

    // trg_tasks_validate_swarm_active rechaza tareas sobre swarms 'archived' — solo los
    // swarms activos/pausados son candidatos válidos para recibir tareas nuevas.
    const activeSwarmIds = swarmRows.filter((row) => row.status !== "archived").map((row) => row.id);
    const taskCount = activeSwarmIds.length * 2;
    await seed(tx, { tasks }, { count: taskCount, seed: tenantSeed + 2 }).refine((f) => ({
      tasks: {
        columns: {
          id: f.uuid(),
          tenantId: f.default({ defaultValue: tenant.id }),
          swarmId: f.valuesFromArray({ values: activeSwarmIds }),
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

    const now = new Date();
    // 12 meses, no 90 días: reports.sp_refresh_reports necesita ejecuciones repartidas
    // en el año completo para que el trend de 12 meses del dashboard (approach.md §6)
    // tenga algo real que mostrar en cada mes, no solo en los últimos ~3.
    const seedWindowStart = new Date(now.getTime() - 365 * DAY_MS);

    // attemptNumber tiene que ser consecutivo por taskId (lo exige trg_executions_validate_attempt_number)
    // y finishedAt solo aplica a estados terminales, siempre después de startedAt (trg_executions_validate_transition)
    // — son tres columnas correlacionadas que drizzle-seed no puede generar juntas, así que se arma a mano.
    const executionRows = taskRows.flatMap((task) => {
      const attemptCount = rng.pick(ATTEMPT_COUNT_POOL);
      // Cada tarea arranca en un punto aleatorio de la ventana, no siempre al inicio —
      // si no, los intentos se amontonan cerca de "ahora" y los meses viejos del trend
      // igual quedan vacíos.
      let startedAt = new Date(seedWindowStart.getTime()
        + rng.float() * (now.getTime() - seedWindowStart.getTime()));

      return Array.from({ length: attemptCount }, (_, index) => {
        if (index > 0) {
          const gapMs = rng.pick(START_GAP_MINUTES_POOL) * 60_000;
          startedAt = new Date(Math.min(startedAt.getTime() + gapMs, now.getTime()));
        }

        const status = rng.pick(EXECUTION_STATUS_POOL);
        const finishedAt = status === "completed" || status === "failed"
          ? new Date(startedAt.getTime() + rng.pick(DURATION_MINUTES_POOL) * 60_000)
          : null;

        return {
          id: generateId(),
          tenantId: tenant.id,
          taskId: task.id,
          attemptNumber: index + 1,
          status,
          startedAt,
          finishedAt,
        };
      });
    });

    if (executionRows.length > 0) await tx.insert(executions).values(executionRows);
  };
};
