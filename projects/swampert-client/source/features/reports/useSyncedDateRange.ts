import { watch, type Ref } from "vue";
import { useDashboardRange } from "@shared/dashboardRange";
import { useDateRangeFilter, type PeriodBucketed } from "@features/reports/useDateRangeFilter";

// Bridges the single range DashboardLayout.vue provides (dashboardRange.ts) into
// useDateRangeFilter.ts's own per-call local range — that file is intocable and has
// no way to accept an external ref, so every view that filters report rows by the
// shared date range goes through this instead of repeating the same inject+watch
// wiring three times (KpisView, TrendsView, DetailView's error section).
export function useSyncedDateRange<T extends PeriodBucketed>(rows: Ref<T[]>) {
  const shared = useDashboardRange();
  const { range, filtered } = useDateRangeFilter(rows);

  watch(shared, (next) => {
    range.value = next;
  }, { immediate: true });

  return { filtered };
}
