<script setup lang="ts">
import { onMounted, ref } from "vue";
import { useReportsData } from "@features/reports/useReportsData";
import { useSyncedDateRange } from "@features/reports/useSyncedDateRange";
import type { SwarmTaskSummaryRow, ErrorSummaryRow } from "@features/reports/reports.client";
import SwarmTaskBreakdown from "@features/reports/components/SwarmTaskBreakdown.vue";
import SwarmTaskBars from "@features/reports/components/SwarmTaskBars.vue";
import ErrorSeverityBreakdown from "@features/reports/components/ErrorSeverityBreakdown.vue";

const { fetchSwarmTasks, fetchErrors } = useReportsData();

const swarmTasks = ref<SwarmTaskSummaryRow[]>([]);
const errorRows = ref<ErrorSummaryRow[]>([]);
const loading = ref(true);

// Solo errorRows pasa por el rango compartido — swarmTasks es un snapshot del
// estado actual sin columna period, nunca debe filtrarse por fecha (regla #3).
const { filtered: filteredErrors } = useSyncedDateRange(errorRows);

onMounted(async () => {
  loading.value = true;
  const [swarmData, errorData] = await Promise.all([fetchSwarmTasks(), fetchErrors()]);
  swarmTasks.value = swarmData;
  errorRows.value = errorData;
  loading.value = false;
});
</script>

<template>
  <div class="space-y-4">
    <!-- items-start: CSS Grid estira las columnas a la misma altura por defecto —
         sin esto, la tarjeta de errores (siempre corta, 4 barras fijas) se inflaba
         para igualar la columna izquierda (crece con la cantidad de swarms),
         dejando un borde vacío enorme debajo de su propio contenido. -->
    <div class="grid grid-cols-1 items-start gap-6 lg:grid-cols-2">
      <div class="space-y-6">
        <SwarmTaskBreakdown :rows="swarmTasks" />
        <SwarmTaskBars :rows="swarmTasks" />
      </div>
      <ErrorSeverityBreakdown :rows="filteredErrors" />
    </div>

    <p v-if="loading" class="text-xs text-muted">Cargando…</p>
  </div>
</template>
