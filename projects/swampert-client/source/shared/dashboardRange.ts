import { inject, type InjectionKey, type Ref } from "vue";

export type DashboardDateRange = [Date, Date] | null;

// useDateRangeFilter.ts (intocable) creates its own local `range` ref per call site
// — it has no way to accept an external one. This InjectionKey is what lets
// DashboardLayout.vue own a single range and hand it down to the 3 route views
// (kpis/trends/detail), which stay mounted as siblings under the same parent
// route and therefore share this provide() across tab switches without a store.
export const dashboardRangeKey: InjectionKey<Ref<DashboardDateRange>> = Symbol("dashboardRange");

// Centralizes the "no provider found" failure mode in one place instead of every
// view repeating `inject(dashboardRangeKey)` and handling `undefined` itself.
export function useDashboardRange(): Ref<DashboardDateRange> {
  const range = inject(dashboardRangeKey);

  if (!range) {
    throw new Error("useDashboardRange() called outside DashboardLayout.vue's provide scope");
  }

  return range;
}
