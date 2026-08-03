---
paths:
  - "projects/swampert-client/**"
---

# Swampert Client Conventions

TypeScript on Vite/Bun, Vue 3 (Composition API), Vue Router, Tailwind v4, Chart.js. Concrete style and structure for this project only — coupling/cohesion/SOLID/smells are covered language-agnostically in `coding.md` and still apply here.

---

## Composition API only

Every component is `<script setup lang="ts">` — this is already the only style in use (`App.vue`) and the only one to add to. No Options API (`export default { data() {...}, methods: {...} }`) anywhere in this project; mixing the two styles across components makes each one harder to read on its own terms for no benefit here.

## Classes over standalone functions — with Vue's own idiom respected

Same default as `engine.md`: a class groups related behavior, dependencies, and state in one place instead of scattering them across module-level functions. Apply it to **non-reactive service-style code** — an API client wrapping calls to the `swampert-engine` backend, a chart-data transformation/formatting module with several related operations, anything that behaves like `TenantScope` or `PasswordHelper` on the engine side.

**Composables stay functions — this is not an exception to negotiate, it's how Vue's reactivity works.** `ref`/`computed`/`reactive` and `<script setup>`'s compiler macros are built around plain functions returning reactive state; a `useSomething()` composable has to be a function for Vue's reactivity system and dependency tracking to work at all. Group related composable logic with plain functions and closures the way Vue itself does, not by wrapping it in a class.

```ts
// Composable — stays a function, this is Vue's own idiom
export function useTaskFilters() {
  const dateRange = ref<[Date, Date] | null>(null);
  const filtered = computed(() => /* ... */);
  return { dateRange, filtered };
}

// Service-style logic — a class, same reasoning as engine.md
export class DashboardApiClient {
  constructor(private readonly baseUrl: string) {}

  async fetchSummary(tenantId: string): Promise<SummaryResponse> {
    /* ... */
  }
}
```

### `erasableSyntaxOnly` changes how a class is written here

`tsconfig.app.json` sets `erasableSyntaxOnly: true`, which the engine's `tsconfig.json` does **not** set. This forbids TypeScript syntax that isn't pure type-stripping — concretely, **no constructor parameter properties** (`constructor(private readonly db: Drizzler) {}`, the shorthand `TenantScope` uses on the engine side) and **no `enum`**. A class here has to declare fields explicitly and assign them in the constructor body:

```ts
// Not allowed under erasableSyntaxOnly — compiles on the engine, not here
export class DashboardApiClient {
  constructor(private readonly baseUrl: string) {}
}

// Required shape in swampert-client
export class DashboardApiClient {
  private readonly baseUrl: string;

  constructor(baseUrl: string) {
    this.baseUrl = baseUrl;
  }
}
```

For a closed set of string values, use a `const` object or a string-literal union instead of `enum` — both are erasable and `enum` is rejected here regardless of the "classes over functions" preference.

## Path aliases, not relative chains

Use the declared aliases instead of relative imports across a boundary — `@assets/*`, `@shared/*`, `@designs/*`, `@features/*` (all under `source/`). They're declared in both `tsconfig.app.json` and `vite.config.ts`; if a new alias is ever added, it has to go in both files or the build and the type-checker disagree about what resolves. See `coding.md` on why crossing a seam without its alias is a coupling smell.

## State management

Default to composables for state shared across a few related components (a filter, a fetch-with-loading-state pattern) — nothing beyond Vue's own reactivity is installed yet (no Pinia, no Vue Query), and that's deliberate for the project's current size, not an oversight to "fix" preemptively. Reach for a dedicated state library only once composables genuinely stop being enough (state needed across unrelated parts of the tree with no natural parent/child relationship) — introducing one before that point is the speculative-generality smell from `coding.md`.

## Strict mode is already on — write to it, don't suppress it

`noUnusedLocals`, `noUnusedParameters`, and `noFallthroughCasesInSwitch` are enabled in `tsconfig.app.json`. Don't leave an unused destructured prop or an intentionally-ignored parameter in place expecting the compiler to allow it — name it as consumed or drop it, and give every `switch` an explicit `break`/`return` per case (or a deliberate fallthrough comment) rather than relying on the compiler to catch a missing one after the fact.
