import { defineStore } from "pinia";
import { ref, computed } from "vue";

import { authApiClient, type UserRole } from "@features/auth/auth.client";

interface StoredSession {
  token: string;
  tenantId: string;
  userId: string;
  role: UserRole;
}

const STORAGE_KEY = "swampert.auth";

function readStoredSession(): StoredSession | null {
  const raw = localStorage.getItem(STORAGE_KEY);
  if (!raw) return null;

  return JSON.parse(raw) as StoredSession;
}

// The one piece of dashboard state that lives in Pinia instead of a composable
// — it's read from unrelated parts of the tree (the router guard, every
// reports.client.ts call) with no natural parent/child relationship between
// them. See .claude/rules/client.md § State management and
// deltas/analytics-dashboard.spec.md § Contexto técnico for why this is the
// one deliberate exception, not a precedent for reaching for Pinia by default.
export const useAuthStore = defineStore("auth", () => {
  const stored = readStoredSession();

  const token = ref<string | null>(stored?.token ?? null);
  const tenantId = ref<string | null>(stored?.tenantId ?? null);
  const userId = ref<string | null>(stored?.userId ?? null);
  const role = ref<UserRole | null>(stored?.role ?? null);

  const isAuthenticated = computed(() => token.value !== null);

  function persist() {
    if (!token.value || !tenantId.value || !userId.value || !role.value) return;

    const session: StoredSession = {
      token: token.value, tenantId: tenantId.value, userId: userId.value, role: role.value,
    };
    localStorage.setItem(STORAGE_KEY, JSON.stringify(session));
  }

  async function login(tenantSlug: string, email: string, password: string) {
    const result = await authApiClient.login(tenantSlug, email, password);

    token.value = result.token;
    tenantId.value = result.tenantId;
    userId.value = result.userId;
    role.value = result.role;

    persist();
  }

  function logout() {
    token.value = null;
    tenantId.value = null;
    userId.value = null;
    role.value = null;

    localStorage.removeItem(STORAGE_KEY);
  }

  return { token, tenantId, userId, role, isAuthenticated, login, logout };
});
