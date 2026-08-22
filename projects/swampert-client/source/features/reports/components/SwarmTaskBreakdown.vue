<script setup lang="ts">
import { computed } from "vue";
import type { SwarmTaskSummaryRow } from "@features/reports/reports.client";
import { TASK_STATUSES, taskStatusColor, taskStatusLabel } from "@features/reports/statusColors";

const props = defineProps<{ rows: SwarmTaskSummaryRow[] }>();

interface SwarmGroup {
  swarmId: string;
  shortId: string;
  total: number;
  statuses: SwarmTaskSummaryRow[];
}

// No endpoint resolves swarmId → a name (confirmed against restful.spec.md, skill
// §7.a) — the truncated id + full uuid in `title` is the accepted, known limitation,
// not a bug to work around here.
const groups = computed<SwarmGroup[]>(() => {
  const bySwarm = new Map<string, SwarmTaskSummaryRow[]>();

  for (const row of props.rows) {
    const list = bySwarm.get(row.swarmId) ?? [];
    list.push(row);
    bySwarm.set(row.swarmId, list);
  }

  return [...bySwarm.entries()]
    .map(([swarmId, statuses]) => ({
      swarmId,
      shortId: `${swarmId.slice(0, 8)}…`,
      total: statuses.reduce((sum, row) => sum + row.taskCount, 0),
      statuses: [...statuses].sort((a, b) => b.taskCount - a.taskCount),
    }))
    .sort((a, b) => b.total - a.total);
});

const maxCount = computed(() => Math.max(1, ...props.rows.map((row) => row.taskCount)));

// Node diameter scales with taskCount so magnitude reads visually, same idea as the
// pulsing dot below: this is a current-state snapshot, not a time series, so size
// (not a line) is what carries the comparison.
function nodeSize(count: number): number {
  const min = 28;
  const max = 64;
  return Math.round(min + (max - min) * (count / maxCount.value));
}
</script>

<template>
  <div class="rounded-lg border border-line bg-panel p-5">
    <div class="mb-3 flex items-center gap-2">
      <p class="text-xs font-medium tracking-wide text-muted uppercase">Tareas por swarm</p>

      <!-- Reemplaza el badge de texto fijo: un punto pulsante es el mismo aviso
           ("esto es estado actual, no responde al filtro") como señal visual
           permanente en vez de una frase larga siempre presente. --trace (no
           --warn) a propósito: es el token documentado como "indicador en vivo"
           en la tabla de colores — --warn ya significa "En curso" en la leyenda
           de abajo, usarlo acá los hacía indistinguibles sin relación real. -->
      <span class="relative flex h-2 w-2" title="Snapshot del estado actual — no responde al filtro de fechas">
        <span class="absolute inline-flex h-full w-full animate-ping rounded-full bg-trace opacity-75"></span>
        <span class="relative inline-flex h-2 w-2 rounded-full bg-trace"></span>
      </span>
    </div>

    <div class="mb-4 flex flex-wrap items-center gap-3 text-[11px] text-muted">
      <span v-for="status in TASK_STATUSES" :key="status" class="flex items-center gap-1.5">
        <span
          class="inline-block h-2.5 w-2.5 rounded-full"
          :style="{ backgroundColor: taskStatusColor(status) }"
        ></span>
        {{ taskStatusLabel(status) }}
      </span>
    </div>

    <div v-if="groups.length === 0" class="text-xs text-muted">Sin swarms con tareas registradas.</div>

    <div v-else class="space-y-4">
      <div v-for="group in groups" :key="group.swarmId" class="flex min-h-16 items-center gap-4">
        <span class="w-20 shrink-0 font-mono text-xs text-muted" :title="group.swarmId">
          {{ group.shortId }}
        </span>

        <div class="flex flex-1 flex-wrap items-center gap-2">
          <!-- Slot de 64px (el tope de nodeSize()) por nodo, en vez de que el
               círculo mismo defina el espacio que ocupa — así un nodo chico y uno
               grande quedan centrados sobre el mismo punto en vez de que el chico
               se vea "flotando" desalineado al lado del grande. -->
          <div
            v-for="status in group.statuses"
            :key="status.taskStatus"
            class="flex h-16 w-16 shrink-0 items-center justify-center"
          >
            <div
              class="flex items-center justify-center rounded-full text-[11px] font-medium text-ink"
              :style="{
                width: `${nodeSize(status.taskCount)}px`,
                height: `${nodeSize(status.taskCount)}px`,
                backgroundColor: taskStatusColor(status.taskStatus),
              }"
              :title="`${taskStatusLabel(status.taskStatus)}: ${status.taskCount}`"
            >
              {{ status.taskCount }}
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
