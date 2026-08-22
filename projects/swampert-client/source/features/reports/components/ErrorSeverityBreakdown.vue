<script setup lang="ts">
import { computed } from "vue";
import type { ErrorSummaryRow } from "@features/reports/reports.client";
import { ERROR_SEVERITIES, severityColor, severityLabel } from "@features/reports/statusColors";

const props = defineProps<{ rows: ErrorSummaryRow[] }>();

interface SeverityTotal {
  severity: string;
  count: number;
}

// rows already comes filtered to the selected date range from DetailView — this
// aggregates across whatever months are visible into one total per severity,
// magnitude being what matters here (skill §3), not per-month detail.
const totals = computed<SeverityTotal[]>(() => {
  const bySeverity = new Map<string, number>(ERROR_SEVERITIES.map((severity) => [severity, 0]));

  for (const row of props.rows) {
    bySeverity.set(row.severity, (bySeverity.get(row.severity) ?? 0) + row.errorCount);
  }

  return ERROR_SEVERITIES.map((severity) => ({ severity, count: bySeverity.get(severity) ?? 0 }));
});

const maxCount = computed(() => Math.max(1, ...totals.value.map((item) => item.count)));
const totalErrors = computed(() => totals.value.reduce((sum, item) => sum + item.count, 0));

// Segunda lectura de los mismos datos, no un pedido nuevo: qué severidad pesa
// más y en qué mes se concentraron — completa la caja con síntesis real en vez
// de dejarla vacía debajo de las 4 barras (totals siempre tiene 4 elementos,
// uno por ERROR_SEVERITIES, así que el reduce con [0] como semilla es seguro).
const topSeverityLabel = computed(() => {
  const top = totals.value.reduce((best, item) => (item.count > best.count ? item : best), totals.value[0]);
  return severityLabel(top.severity);
});

// period ("YYYY-MM-DD") es dato de calendario, no un instante — timeZone: "UTC"
// evita el mismo corrimiento de mes ya encontrado y corregido en
// TrendChart.vue/MonthlyLogbook.vue.
function formatMonthLabel(period: string): string {
  return new Date(period).toLocaleDateString("es-CR", { month: "short", year: "numeric", timeZone: "UTC" });
}

interface PeakMonth {
  label: string;
  count: number;
}

const peakMonth = computed<PeakMonth | null>(() => {
  const byPeriod = new Map<string, number>();

  for (const row of props.rows) {
    byPeriod.set(row.period, (byPeriod.get(row.period) ?? 0) + row.errorCount);
  }

  let best: { period: string; count: number } | null = null;
  for (const [period, count] of byPeriod) {
    if (!best || count > best.count) best = { period, count };
  }

  return best ? { label: formatMonthLabel(best.period), count: best.count } : null;
});
</script>

<template>
  <div class="rounded-lg border border-line bg-panel p-5">
    <p class="mb-4 text-xs font-medium tracking-wide text-muted uppercase">Errores por severidad</p>

    <div v-if="totalErrors === 0" class="text-xs text-muted">
      Sin errores registrados en el rango seleccionado.
    </div>

    <template v-else>
      <div class="space-y-3">
        <div v-for="item in totals" :key="item.severity" class="flex items-center gap-3">
          <span class="w-16 shrink-0 text-xs text-muted">{{ severityLabel(item.severity) }}</span>

          <div class="h-2.5 flex-1 overflow-hidden rounded-full bg-ink">
            <div
              class="h-full rounded-full transition-all"
              :style="{
                width: `${(item.count / maxCount) * 100}%`,
                backgroundColor: severityColor(item.severity),
              }"
            ></div>
          </div>

          <span class="w-8 shrink-0 text-right font-mono text-xs text-text">{{ item.count }}</span>
        </div>
      </div>

      <div class="mt-4 space-y-1.5 border-t border-line pt-3 text-xs">
        <div class="flex items-center justify-between">
          <span class="text-muted">Total en el rango</span>
          <span class="font-mono text-text">{{ totalErrors }} {{ totalErrors === 1 ? "error" : "errores" }}</span>
        </div>

        <div class="flex items-center justify-between">
          <span class="text-muted">Severidad más frecuente</span>
          <span class="font-mono text-text">{{ topSeverityLabel }}</span>
        </div>

        <div v-if="peakMonth" class="flex items-center justify-between">
          <span class="text-muted">Mes con más errores</span>
          <span class="font-mono text-text">{{ peakMonth.label }} ({{ peakMonth.count }})</span>
        </div>
      </div>
    </template>
  </div>
</template>
