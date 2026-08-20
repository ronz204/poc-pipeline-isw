import { ref, computed, type Ref } from "vue";

export interface PeriodBucketed {
  period: string;
}

// Recorta un arreglo ya agregado (traído una sola vez del backend) por rango
// de fechas, en el cliente — no vuelve a pedir datos al servidor por cada
// cambio de rango. No aplica a swarm_task_summary, que no tiene columna
// `period` (deltas/analytics-dashboard.spec.md § Riesgos, punto 2).
export function useDateRangeFilter<T extends PeriodBucketed>(rows: Ref<T[]>) {
  const range = ref<[Date, Date] | null>(null);

  const filtered = computed(() => {
    if (!range.value) return rows.value;

    const [start, end] = range.value;
    return rows.value.filter((row) => {
      const period = new Date(row.period);
      return period >= start && period <= end;
    });
  });

  return { range, filtered };
}
