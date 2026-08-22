<script setup lang="ts">
import { computed, ref } from "vue";
import type { ChartConfiguration } from "chart.js/auto";
import { useChart } from "@shared/useChart";
import type { MonthlyExecutionSummaryRow } from "@features/reports/reports.client";

const props = defineProps<{ rows: MonthlyExecutionSummaryRow[] }>();

type Metric = "executions" | "cost";
const metric = ref<Metric>("executions");

const sorted = computed(() => [...props.rows].sort((a, b) => a.period.localeCompare(b.period)));

// period ("YYYY-MM-DD") is calendar data, not an instant — new Date(period) parses
// it as UTC midnight, and formatting that in the browser's local timezone can roll
// it back to the previous day (verified: America/Guatemala, UTC-6, turned
// "2026-08-01" into "jul 26" instead of "ago 26"). timeZone: "UTC" pins the
// formatter to the same calendar day the string actually names.
function formatMonthLabel(period: string): string {
  return new Date(period).toLocaleDateString("es-CR", { month: "short", year: "2-digit", timeZone: "UTC" });
}

// Canvas 2D contexts don't resolve CSS custom properties on their own — chart.js
// needs a literal color string, so the design tokens from style.css are read once
// per config rebuild instead of a second hardcoded hex living in this file too.
function resolveToken(token: string): string {
  return getComputedStyle(document.documentElement).getPropertyValue(token).trim();
}

const config = computed<ChartConfiguration<"line">>(() => {
  const labels = sorted.value.map((row) => formatMonthLabel(row.period));
  const values = sorted.value.map((row) =>
    metric.value === "executions" ? row.executionCount : Number(row.totalCost),
  );

  const signal = resolveToken("--signal");
  const muted = resolveToken("--text-muted");
  const line = resolveToken("--border");

  return {
    type: "line",
    data: {
      labels,
      datasets: [{
        label: metric.value === "executions" ? "Ejecuciones" : "Costo total (USD)",
        data: values,
        borderColor: signal,
        backgroundColor: signal,
        tension: 0.25,
        pointRadius: 3,
      }],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      scales: {
        x: { ticks: { color: muted }, grid: { color: line } },
        y: { ticks: { color: muted }, grid: { color: line }, beginAtZero: true },
      },
      plugins: {
        legend: { display: false },
      },
    },
  };
});

const canvasRef = ref<HTMLCanvasElement | null>(null);
useChart(canvasRef, config);
</script>

<template>
  <div class="rounded-lg border border-line bg-panel p-5">
    <div class="mb-4 flex items-center justify-between">
      <p class="text-xs font-medium tracking-wide text-muted uppercase">Tendencia mensual</p>

      <div class="flex overflow-hidden rounded-md border border-line text-xs">
        <button
          type="button"
          class="px-3 py-1 transition"
          :class="metric === 'executions' ? 'bg-signal text-white' : 'text-muted hover:text-text'"
          @click="metric = 'executions'"
        >
          Ejecuciones
        </button>
        <button
          type="button"
          class="px-3 py-1 transition"
          :class="metric === 'cost' ? 'bg-signal text-white' : 'text-muted hover:text-text'"
          @click="metric = 'cost'"
        >
          Costo
        </button>
      </div>
    </div>

    <div class="h-64">
      <canvas ref="canvasRef"></canvas>
    </div>

    <p v-if="rows.length === 0" class="mt-3 text-xs text-muted">Sin datos en el rango seleccionado.</p>
  </div>
</template>
