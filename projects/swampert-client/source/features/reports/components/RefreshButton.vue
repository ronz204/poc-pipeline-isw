<script setup lang="ts">
withDefaults(defineProps<{
  loading: boolean;
  feedback?: string | null;
}>(), {
  feedback: null,
});

const emit = defineEmits<{ refresh: [] }>();
</script>

<template>
  <div class="flex flex-col gap-2">
    <div class="flex flex-wrap items-center gap-3">
      <button
        type="button"
        :disabled="loading"
        class="rounded-md border border-line bg-panel px-4 py-2 text-sm font-medium text-text transition hover:border-signal disabled:opacity-50"
        @click="emit('refresh')"
      >
        {{ loading ? "Actualizando…" : "Actualizar reportes" }}
      </button>
    </div>

    <p v-if="feedback" class="text-xs text-trace">{{ feedback }}</p>
  </div>
</template>
