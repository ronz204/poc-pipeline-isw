<script setup lang="ts">
import { computed, onMounted, ref } from "vue";
import { useReportsData } from "@features/reports/useReportsData";
import { useSyncedDateRange } from "@features/reports/useSyncedDateRange";
import type { MonthlyExecutionSummaryRow } from "@features/reports/reports.client";
import KpiCard from "@features/reports/components/KpiCard.vue";
import MonthlyLogbook from "@features/reports/components/MonthlyLogbook.vue";
import RefreshButton from "@features/reports/components/RefreshButton.vue";

const { fetchMonthlyExecutions, refreshReports } = useReportsData();

const rows = ref<MonthlyExecutionSummaryRow[]>([]);
const loading = ref(true);
const refreshing = ref(false);
const refreshFeedback = ref<string | null>(null);

const { filtered } = useSyncedDateRange(rows);

async function load() {
  loading.value = true;
  rows.value = await fetchMonthlyExecutions();
  loading.value = false;
}

onMounted(load);

const totalExecutions = computed(() => filtered.value.reduce((sum, row) => sum + row.executionCount, 0));

const totalCostFormatted = computed(() => {
  const total = filtered.value.reduce((sum, row) => sum + Number(row.totalCost), 0);
  return new Intl.NumberFormat("es-CR", { style: "currency", currency: "USD" }).format(total);
});

function formatDuration(totalSeconds: number): string {
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = Math.round(totalSeconds % 60);
  return `${minutes}m ${seconds}s`;
}

// Promedia solo los meses con avgDurationSeconds no-null; si al menos uno visible es
// null lo dice explícito, si TODOS son null muestra "sin datos aún" — nunca 0
// (spec §7 "Duración promedio con meses null", regla #4).
const durationSummary = computed(() => {
  const withData = filtered.value.filter((row) => row.avgDurationSeconds !== null);

  if (withData.length === 0) {
    return { value: "Sin datos aún", caption: undefined, muted: true };
  }

  const avgSeconds = withData.reduce((sum, row) => sum + Number(row.avgDurationSeconds), 0) / withData.length;
  const value = formatDuration(avgSeconds);

  if (withData.length < filtered.value.length) {
    return {
      value,
      caption: `Promedio parcial (${withData.length} de ${filtered.value.length} meses)`,
      muted: false,
    };
  }

  return { value, caption: undefined, muted: false };
});

// Un tick por mes conocido (no solo los filtrados): --trace para el mes actual,
// --signal para los que están dentro del rango elegido, --border para los que
// quedan fuera — referencia visual directa al concepto de bitácora (skill §3).
const traceTicks = computed(() => {
  const sortedRows = [...rows.value].sort((a, b) => a.period.localeCompare(b.period));
  const inRangePeriods = new Set(filtered.value.map((row) => row.period));
  const currentMonth = new Date().toISOString().slice(0, 7);

  return sortedRows.map((row) => ({
    period: row.period,
    inRange: inRangePeriods.has(row.period),
    isCurrent: row.period.slice(0, 7) === currentMonth,
  }));
});

async function onRefresh() {
  refreshing.value = true;
  refreshFeedback.value = null;

  // Built via Date.UTC (not the local-time constructor) so its later
  // .toISOString()/JSON serialization lands on the same calendar day these local
  // year/month components name — the local constructor would risk rolling back a
  // day for any timezone ahead of UTC once serialized (verified against
  // TrendChart.vue's identical bug, see its formatMonthLabel comment).
  const today = new Date();
  const period = new Date(Date.UTC(today.getFullYear(), today.getMonth(), 1));

  await refreshReports(period);
  rows.value = await fetchMonthlyExecutions();

  refreshFeedback.value = "Reportes actualizados.";
  refreshing.value = false;
}
</script>

<template>
  <div class="space-y-6">
    <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
      <KpiCard label="Ejecuciones totales" :value="String(totalExecutions)" />
      <KpiCard
        label="Duración promedio"
        :value="durationSummary.value"
        :caption="durationSummary.caption"
        :muted="durationSummary.muted"
      />
      <KpiCard label="Costo total" :value="totalCostFormatted" />
    </div>

    <div v-if="traceTicks.length > 0" class="flex gap-1">
      <div
        v-for="tick in traceTicks"
        :key="tick.period"
        class="h-1.5 flex-1 rounded-full"
        :class="tick.isCurrent ? 'bg-trace' : tick.inRange ? 'bg-signal' : 'bg-line'"
        :title="tick.period"
      ></div>
    </div>

    <MonthlyLogbook :rows="filtered" />

    <RefreshButton :loading="refreshing" :feedback="refreshFeedback" @refresh="onRefresh" />

    <p v-if="loading" class="text-xs text-muted">Cargando…</p>
  </div>
</template>
