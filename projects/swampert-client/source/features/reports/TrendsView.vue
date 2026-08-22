<script setup lang="ts">
import { onMounted, ref } from "vue";
import { useReportsData } from "@features/reports/useReportsData";
import { useSyncedDateRange } from "@features/reports/useSyncedDateRange";
import type { MonthlyExecutionSummaryRow } from "@features/reports/reports.client";
import TrendChart from "@features/reports/components/TrendChart.vue";

const { fetchMonthlyExecutions } = useReportsData();

const rows = ref<MonthlyExecutionSummaryRow[]>([]);
const loading = ref(true);

const { filtered } = useSyncedDateRange(rows);

onMounted(async () => {
  loading.value = true;
  // Mismos ~12 meses que KpisView — fetchMonthlyExecutions() está cacheado por
  // tenantId en useReportsData.ts (spec §7.e), así que si KPIs ya cargó en esta
  // sesión de /dashboard/*, esto resuelve del cache sin un segundo request.
  rows.value = await fetchMonthlyExecutions();
  loading.value = false;
});
</script>

<template>
  <div class="space-y-6">
    <TrendChart :rows="filtered" />
    <p v-if="loading" class="text-xs text-muted">Cargando…</p>
  </div>
</template>
