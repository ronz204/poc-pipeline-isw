<script setup lang="ts">
withDefaults(defineProps<{
  label: string;
  value: string;
  caption?: string;
  muted?: boolean;
}>(), {
  caption: undefined,
  muted: false,
});
</script>

<template>
  <div class="rounded-lg border border-line bg-panel p-5">
    <p class="text-xs font-medium tracking-wide text-muted uppercase">{{ label }}</p>
    <p class="mt-2 font-mono text-3xl font-semibold" :class="muted ? 'text-muted' : 'text-text'">
      {{ value }}
    </p>
    <p v-if="caption" class="mt-1 text-xs text-muted">{{ caption }}</p>
  </div>
</template>
