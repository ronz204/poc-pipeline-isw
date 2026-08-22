<script setup lang="ts">
import { provide, ref, watch } from "vue";
import { RouterLink, RouterView, useRoute } from "vue-router";

import { useAuthStore } from "@features/auth/auth.store";
import { getTenantLabel } from "@features/auth/tenantLabel";
import { useReportsData } from "@features/reports/useReportsData";
import { dashboardRangeKey, type DashboardDateRange } from "@shared/dashboardRange";

const route = useRoute();
const authStore = useAuthStore();
const { logout } = useReportsData();

// DashboardLayout no se desmonta al navegar entre kpis/trends/detail (son rutas
// hijas del mismo padre) — un solo provide() acá es lo que hace que las 3 vistas
// reaccionen al mismo rango, en vez de que cada useDateRangeFilter() cree el suyo
// (spec §7.d, dashboardRange.ts).
const range = ref<DashboardDateRange>(null);
provide(dashboardRangeKey, range);

const tenantDisplay = getTenantLabel() ?? authStore.tenantId ?? "—";

const tabs = [
  { name: "dashboard-kpis", label: "KPIs" },
  { name: "dashboard-trends", label: "Tendencias" },
  { name: "dashboard-detail", label: "Detalle" },
] as const;

// Strings separados en vez de derivar directo de `range`: el filtro solo debe
// activarse cuando AMBAS fechas están elegidas — si el fin faltante se
// completara solo con "hoy" apenas se elige el inicio, sería un filtro que el
// usuario no pidió.
const startInput = ref("");
const endInput = ref("");
const rangeError = ref<string | null>(null);

// Dos <input type="date"> nativos no impiden por sí solos que el inicio quede
// después del fin — sin este chequeo, un rango invertido pasaba silencioso a
// useDateRangeFilter (period >= inicio && period <= fin nunca se cumple) y el
// dashboard se veía vacío en las 3 pantallas sin ninguna explicación (bug real,
// encontrado probando la UI). En vez de aplicar ese filtro imposible, se limpia
// a "sin filtro" y se explicita el motivo.
watch([startInput, endInput], ([start, end]) => {
  if (!start || !end) {
    rangeError.value = null;
    range.value = null;
    return;
  }

  const startDate = new Date(start);
  const endDate = new Date(end);

  if (startDate > endDate) {
    rangeError.value = "La fecha de inicio no puede ser posterior a la de fin — no se aplicó ningún filtro.";
    range.value = null;
    return;
  }

  rangeError.value = null;
  range.value = [startDate, endDate];
});

function clearRange() {
  startInput.value = "";
  endInput.value = "";
}

async function onLogout() {
  await logout();
}
</script>

<template>
  <div class="flex min-h-screen bg-ink">
    <aside class="flex w-56 flex-shrink-0 flex-col border-r border-line bg-panel">
      <div class="px-5 py-6">
        <p class="font-mono text-sm font-semibold tracking-widest text-text">SWAMPERT</p>
        <p class="mt-1 truncate text-xs text-muted" :title="tenantDisplay">{{ tenantDisplay }}</p>
      </div>

      <nav class="flex flex-col gap-1 px-3">
        <RouterLink
          v-for="tab in tabs"
          :key="tab.name"
          :to="{ name: tab.name }"
          class="rounded-md px-3 py-2 text-sm font-medium transition"
          :class="route.name === tab.name
            ? 'bg-signal/15 text-signal'
            : 'text-muted hover:bg-line/40 hover:text-text'"
        >
          {{ tab.label }}
        </RouterLink>
      </nav>

      <div class="mt-auto border-t border-line px-3 py-4">
        <button
          type="button"
          class="w-full rounded-md px-3 py-2 text-left text-sm text-muted transition hover:bg-critical/10 hover:text-critical"
          @click="onLogout"
        >
          Cerrar sesión
        </button>
      </div>
    </aside>

    <div class="flex flex-1 flex-col">
      <header class="flex flex-col gap-2 border-b border-line bg-panel px-6 py-4">
        <div class="flex flex-wrap items-center gap-3">
          <span class="text-xs font-medium tracking-wide text-muted uppercase">Rango de fechas</span>

          <input
            v-model="startInput"
            type="date"
            class="rounded-md border px-2 py-1 text-sm text-text outline-none focus:border-signal"
            :class="rangeError ? 'border-critical' : 'border-line'"
          />
          <span class="text-muted">–</span>
          <input
            v-model="endInput"
            type="date"
            class="rounded-md border px-2 py-1 text-sm text-text outline-none focus:border-signal"
            :class="rangeError ? 'border-critical' : 'border-line'"
          />

          <button
            v-if="startInput || endInput"
            type="button"
            class="text-xs text-muted underline-offset-2 hover:text-text hover:underline"
            @click="clearRange"
          >
            Limpiar
          </button>
        </div>

        <p v-if="rangeError" class="text-xs text-critical" role="alert">{{ rangeError }}</p>
      </header>

      <main class="flex-1 overflow-y-auto p-6">
        <RouterView />
      </main>
    </div>
  </div>
</template>
