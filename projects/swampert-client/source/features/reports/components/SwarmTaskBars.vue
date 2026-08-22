<script setup lang="ts">
import { computed } from "vue";
import type { SwarmTaskSummaryRow } from "@features/reports/reports.client";
import { TASK_STATUSES, taskStatusColor, taskStatusLabel, type TaskStatus } from "@features/reports/statusColors";

const props = defineProps<{ rows: SwarmTaskSummaryRow[] }>();

interface BarSegment {
  status: TaskStatus;
  count: number;
  percent: number;
}

interface SwarmBar {
  swarmId: string;
  shortId: string;
  total: number;
  segments: BarSegment[];
}

// Same grouping as SwarmTaskBreakdown.vue, reshaped into one stacked bar per
// swarm instead of a cluster of nodes — a second, independent read of the same
// rows (props, no fetch of its own), not a variant sharing state with it.
const bars = computed<SwarmBar[]>(() => {
  const bySwarm = new Map<string, SwarmTaskSummaryRow[]>();

  for (const row of props.rows) {
    const list = bySwarm.get(row.swarmId) ?? [];
    list.push(row);
    bySwarm.set(row.swarmId, list);
  }

  return [...bySwarm.entries()]
    .map(([swarmId, statuses]) => {
      const counts = Object.fromEntries(TASK_STATUSES.map((status) => [status, 0])) as Record<TaskStatus, number>;
      for (const row of statuses) counts[row.taskStatus as TaskStatus] = row.taskCount;

      const total = statuses.reduce((sum, row) => sum + row.taskCount, 0);

      // Fixed TASK_STATUSES order (not sorted by count) so every bar's segments
      // line up the same way — that's what makes comparing bars across swarms
      // actually readable.
      const segments = TASK_STATUSES
        .filter((status) => counts[status] > 0)
        .map((status) => ({
          status,
          count: counts[status],
          percent: total > 0 ? (counts[status] / total) * 100 : 0,
        }));

      return { swarmId, shortId: `${swarmId.slice(0, 8)}…`, total, segments };
    })
    .sort((a, b) => b.total - a.total);
});
</script>

<template>
  <div class="rounded-lg border border-line bg-panel p-5">
    <p class="mb-4 text-xs font-medium tracking-wide text-muted uppercase">
      Tareas por swarm — proporción por estado
    </p>

    <div class="mb-4 flex flex-wrap items-center gap-3 text-[11px] text-muted">
      <span v-for="status in TASK_STATUSES" :key="status" class="flex items-center gap-1.5">
        <span
          class="inline-block h-2.5 w-2.5 rounded-full"
          :style="{ backgroundColor: taskStatusColor(status) }"
        ></span>
        {{ taskStatusLabel(status) }}
      </span>
    </div>

    <div v-if="bars.length === 0" class="text-xs text-muted">Sin swarms con tareas registradas.</div>

    <div v-else class="space-y-3">
      <div v-for="bar in bars" :key="bar.swarmId" class="flex items-center gap-3">
        <span class="w-20 shrink-0 font-mono text-xs text-muted" :title="bar.swarmId">{{ bar.shortId }}</span>

        <div class="flex h-4 flex-1 overflow-hidden rounded-full bg-ink">
          <div
            v-for="segment in bar.segments"
            :key="segment.status"
            class="h-full transition-all"
            :style="{ width: `${segment.percent}%`, backgroundColor: taskStatusColor(segment.status) }"
            :title="`${taskStatusLabel(segment.status)}: ${segment.count}`"
          ></div>
        </div>

        <span class="w-8 shrink-0 text-right font-mono text-xs text-text">{{ bar.total }}</span>
      </div>
    </div>
  </div>
</template>
