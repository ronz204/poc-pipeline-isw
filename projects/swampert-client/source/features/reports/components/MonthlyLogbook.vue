<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from "vue";
import type { MonthlyExecutionSummaryRow } from "@features/reports/reports.client";

const props = defineProps<{ rows: MonthlyExecutionSummaryRow[] }>();

interface LogbookEntry {
  period: string;
  refreshedAtRaw: string;
  monthLabel: string;
  executionCount: number;
  durationLabel: string;
  durationIsNull: boolean;
  costFormatted: string;
  costPercent: number;
  relativeTime: string;
  isLatest: boolean;
  isRecentlyUpdated: boolean;
}

const currencyFormatter = new Intl.NumberFormat("es-CR", { style: "currency", currency: "USD" });

// "actualizado ahora" only makes sense for a few minutes — past that it's just
// the most recent row, not something that "just" happened (found live: it kept
// saying "ahora" next to "hace 23 minutos", a contradiction).
const RECENTLY_UPDATED_WINDOW_MS = 2 * 60 * 1000;

// Drives both the relative-time text and the recently-updated window forward
// while the screen stays open, without needing new data from the server —
// otherwise "hace unos segundos" would freeze at whatever it said on the last
// fetch instead of actually ticking.
const now = ref(Date.now());
let clockId: ReturnType<typeof setInterval> | undefined;

onMounted(() => {
  clockId = setInterval(() => { now.value = Date.now(); }, 15_000);
});

onUnmounted(() => {
  if (clockId !== undefined) clearInterval(clockId);
});

// period ("YYYY-MM-DD") is calendar data, not an instant — new Date(period)
// parses it as UTC midnight; timeZone: "UTC" pins the formatter to that same
// calendar day instead of rolling it back a day in a timezone behind UTC (same
// bug already found and fixed once in TrendChart.vue's formatMonthLabel).
function formatMonthLabel(period: string): string {
  return new Date(period).toLocaleDateString("es-CR", { month: "short", year: "numeric", timeZone: "UTC" });
}

function formatDuration(totalSeconds: number): string {
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = Math.round(totalSeconds % 60);
  return `${minutes}m ${seconds}s`;
}

function formatRelativeTime(iso: string, nowMs: number): string {
  const diffSeconds = Math.max(0, Math.round((nowMs - new Date(iso).getTime()) / 1000));

  if (diffSeconds < 60) return "hace unos segundos";

  const diffMinutes = Math.round(diffSeconds / 60);
  if (diffMinutes < 60) return `hace ${diffMinutes} minuto${diffMinutes === 1 ? "" : "s"}`;

  const diffHours = Math.round(diffMinutes / 60);
  if (diffHours < 24) return `hace ${diffHours} hora${diffHours === 1 ? "" : "s"}`;

  const diffDays = Math.round(diffHours / 24);
  if (diffDays < 30) return `hace ${diffDays} día${diffDays === 1 ? "" : "s"}`;

  const diffMonths = Math.round(diffDays / 30);
  if (diffMonths < 12) return `hace ${diffMonths} mes${diffMonths === 1 ? "" : "es"}`;

  const diffYears = Math.round(diffMonths / 12);
  return `hace ${diffYears} año${diffYears === 1 ? "" : "s"}`;
}

// Proportional to the max of the VISIBLE range (props.rows), not a fixed scale
// — same principle ErrorSeverityBreakdown.vue already uses for its bars.
const entries = computed<LogbookEntry[]>(() => {
  const nowMs = now.value; // dependency: re-run as the clock ticks, not just when rows change

  if (props.rows.length === 0) return [];

  const maxCost = Math.max(1, ...props.rows.map((row) => Number(row.totalCost)));
  const latestRefresh = Math.max(...props.rows.map((row) => new Date(row.refreshedAt).getTime()));

  return [...props.rows]
    .sort((a, b) => b.period.localeCompare(a.period))
    .map((row) => {
      const cost = Number(row.totalCost);
      const refreshedAtMs = new Date(row.refreshedAt).getTime();
      const isLatest = refreshedAtMs === latestRefresh;

      return {
        period: row.period,
        refreshedAtRaw: row.refreshedAt,
        monthLabel: formatMonthLabel(row.period),
        executionCount: row.executionCount,
        durationLabel: row.avgDurationSeconds === null
          ? "sin datos aún"
          : formatDuration(Number(row.avgDurationSeconds)),
        durationIsNull: row.avgDurationSeconds === null,
        costFormatted: currencyFormatter.format(cost),
        costPercent: (cost / maxCost) * 100,
        relativeTime: formatRelativeTime(row.refreshedAt, nowMs),
        isLatest,
        isRecentlyUpdated: isLatest && (nowMs - refreshedAtMs) < RECENTLY_UPDATED_WINDOW_MS,
      };
    });
});
</script>

<template>
  <div>
    <p class="mb-3 text-xs font-medium tracking-wide text-muted uppercase">Bitácora mensual</p>

    <div v-if="entries.length === 0" class="text-xs text-muted">Sin datos en el rango seleccionado.</div>

    <div v-else class="space-y-2">
      <!-- La key incluye refreshedAtRaw a propósito: cuando ese mes se recalcula
           de verdad (ej. al hacer click en "Actualizar reportes"), Vue trata la
           fila como un nodo nuevo y el destello (.animate-row-flash) se
           reproduce de cero — no depende de un booleano que ya estaba en true
           y por eso no se repetiría en un segundo click seguido. -->
      <div
        v-for="entry in entries"
        :key="`${entry.period}::${entry.refreshedAtRaw}`"
        class="rounded-r-md bg-panel py-3 pr-4 pl-4"
        :class="[
          entry.isLatest ? 'border-l-[6px] border-trace' : 'border-l-4 border-border',
          entry.isLatest ? 'animate-row-flash' : '',
        ]"
      >
        <div class="flex flex-wrap items-center justify-between gap-2">
          <span class="font-mono text-sm font-medium" :class="entry.isLatest ? 'text-trace' : 'text-text'">
            {{ entry.monthLabel }}
          </span>

          <div class="flex items-center gap-3">
            <!-- Solo aparece dentro de la ventana de "recién pasó" — evita el
                 contradictorio "actualizado ahora" + "hace 23 minutos" que se
                 veía antes, cuando esto no tenía límite de tiempo. -->
            <span
              v-if="entry.isRecentlyUpdated"
              class="flex items-center gap-1.5 rounded-full border border-trace/40 bg-trace/10 px-2 py-0.5 text-[11px] font-medium text-trace"
            >
              <span class="h-1.5 w-1.5 rounded-full bg-trace"></span>
              actualizado ahora
            </span>
            <span class="font-mono text-[11px] text-muted">{{ entry.relativeTime }}</span>
          </div>
        </div>

        <div class="mt-3 flex flex-wrap items-center gap-x-6 gap-y-2 text-xs">
          <span class="font-mono text-text">
            {{ entry.executionCount }} <span class="text-muted">ejecuciones</span>
          </span>

          <span class="font-mono" :class="entry.durationIsNull ? 'text-warn' : 'text-text'">
            {{ entry.durationLabel }}
          </span>

          <div class="flex min-w-40 flex-1 items-center gap-2">
            <div class="h-1.5 flex-1 overflow-hidden rounded-full bg-ink">
              <div
                class="h-full rounded-full transition-all"
                :style="{
                  width: `${entry.costPercent}%`,
                  backgroundColor: entry.isLatest ? 'var(--trace)' : 'var(--signal)',
                }"
              ></div>
            </div>
            <span class="shrink-0 font-mono text-text">{{ entry.costFormatted }}</span>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
