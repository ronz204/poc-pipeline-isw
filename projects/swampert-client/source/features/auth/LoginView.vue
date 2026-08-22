<script setup lang="ts">
import { ref } from "vue";
import { useRouter } from "vue-router";
import { useAuthStore } from "@features/auth/auth.store";
import { setTenantLabel } from "@features/auth/tenantLabel";

const router = useRouter();
const authStore = useAuthStore();

const tenantSlug = ref("");
const email = ref("");
const password = ref("");
const errorMessage = ref<string | null>(null);
const submitting = ref(false);

async function onSubmit() {
  errorMessage.value = null;
  submitting.value = true;

  try {
    await authStore.login(tenantSlug.value, email.value, password.value);
    setTenantLabel(tenantSlug.value);
    await router.push({ name: "dashboard-kpis" });
  } catch {
    // Deliberadamente genérico: el backend nunca distingue tenant desconocido,
    // email desconocido, password incorrecta o usuario inactivo (resistencia a
    // enumeración, regla #7 del skill) — inspeccionar el body del error para
    // dar un mensaje distinto por campo iría en contra de eso a propósito.
    errorMessage.value = "Credenciales inválidas";
  } finally {
    submitting.value = false;
  }
}
</script>

<template>
  <div class="flex min-h-screen items-center justify-center bg-ink px-4">
    <form
      class="w-full max-w-sm rounded-lg border border-line bg-panel p-8 shadow-xl shadow-black/30"
      @submit.prevent="onSubmit"
    >
      <p class="font-mono text-sm font-semibold tracking-widest text-text">SWAMPERT</p>
      <p class="mt-1 mb-6 text-sm text-muted">Consola de auditoría de swarms</p>

      <label class="mb-4 block">
        <span class="mb-1 block text-xs font-medium tracking-wide text-muted uppercase">Organización</span>
        <input
          v-model="tenantSlug"
          type="text"
          required
          autocomplete="organization"
          placeholder="nimbus-swarm"
          class="w-full rounded-md border border-line bg-ink px-3 py-2 text-sm text-text outline-none focus:border-signal"
        />
      </label>

      <label class="mb-4 block">
        <span class="mb-1 block text-xs font-medium tracking-wide text-muted uppercase">Correo</span>
        <input
          v-model="email"
          type="email"
          required
          autocomplete="email"
          placeholder="tu@empresa.com"
          class="w-full rounded-md border border-line bg-ink px-3 py-2 text-sm text-text outline-none focus:border-signal"
        />
      </label>

      <label class="mb-6 block">
        <span class="mb-1 block text-xs font-medium tracking-wide text-muted uppercase">Contraseña</span>
        <input
          v-model="password"
          type="password"
          required
          autocomplete="current-password"
          class="w-full rounded-md border border-line bg-ink px-3 py-2 text-sm text-text outline-none focus:border-signal"
        />
      </label>

      <p v-if="errorMessage" class="mb-4 text-sm text-critical" role="alert">{{ errorMessage }}</p>

      <button
        type="submit"
        :disabled="submitting"
        class="w-full rounded-md bg-signal px-4 py-2 text-sm font-medium text-white transition disabled:opacity-50"
      >
        {{ submitting ? "Ingresando…" : "Ingresar" }}
      </button>
    </form>
  </div>
</template>
