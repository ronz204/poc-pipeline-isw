import { Chart, type ChartConfiguration, type ChartType } from "chart.js/auto";
import { onMounted, onUnmounted, shallowRef, watch, type Ref } from "vue";

// Chart.js owns non-reactive internal state (canvas contexts, animation frames) —
// a plain ref() would make Vue try to deep-proxy the Chart instance, which chart.js
// does not expect and can corrupt. shallowRef keeps the instance itself opaque to
// Vue's reactivity while config/data changes still flow through the watch below.
export function useChart<TType extends ChartType = ChartType>(
  canvasRef: Ref<HTMLCanvasElement | null>,
  config: Ref<ChartConfiguration<TType>>,
) {
  const chart = shallowRef<Chart<TType> | null>(null);

  function destroy() {
    chart.value?.destroy();
    chart.value = null;
  }

  function create() {
    if (!canvasRef.value) return;
    chart.value = new Chart(canvasRef.value, config.value);
  }

  onMounted(create);
  onUnmounted(destroy);

  // Re-creating the whole Chart instance on every data change would flash/reset
  // zoom-less state for no reason — updating .data/.options in place and calling
  // update() is what chart.js's own docs recommend for reactive frameworks.
  watch(config, (next) => {
    if (!chart.value) {
      create();
      return;
    }

    chart.value.data = next.data;
    if (next.options) chart.value.options = next.options;
    chart.value.update();
  });

  return { chart };
}
