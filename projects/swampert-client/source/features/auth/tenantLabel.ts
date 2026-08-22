const STORAGE_KEY = "swampert.tenantLabel";

// auth.store.ts (intocable) persists tenantId (a UUID) but never the tenantSlug the
// user actually typed at login — there is no endpoint that resolves one back into
// the other. This is a deliberately separate localStorage key, not a field bolted
// onto the auth store, so the "don't touch already-complete files" boundary holds.
export function setTenantLabel(slug: string): void {
  localStorage.setItem(STORAGE_KEY, slug);
}

// null on a restored session whose localStorage predates this field — callers must
// fall back to auth.store.ts's tenantId (the UUID) rather than leave the UI blank.
export function getTenantLabel(): string | null {
  return localStorage.getItem(STORAGE_KEY);
}

export function clearTenantLabel(): void {
  localStorage.removeItem(STORAGE_KEY);
}
