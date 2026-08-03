---
paths:
  - "projects/swampert-engine/**"
---

# Swampert Engine Conventions

TypeScript on Bun, backend (ElysiaJS) and data layer (Drizzle ORM over Postgres). Concrete style and structure for this project only — coupling/cohesion/SOLID/smells are covered language-agnostically in `coding.md` and still apply here.

---

## Classes over standalone functions

Default to a class when a piece of logic groups related behavior, wraps a dependency, or carries state across calls — not a standalone exported function. This is a deliberate choice over the more common TypeScript functional style: a class keeps related operations, their shared state, and their dependencies in one place instead of scattered across module-level functions and closures.

```ts
// Preferred — a class groups related operations and their shared dependency
export class TenantScope {
  constructor(private readonly db: Drizzler) {}

  public async run<T>(tenantId: string, work: (tx: TenantTx) => Promise<T>) {
    return this.db.transaction(async (tx) => {
      await tx.execute(sql`SELECT set_config('app.current_tenant_id', ${tenantId}, true)`);
      return work(tx);
    });
  }
}
```

This applies whether the class holds instance state (`SeededRandom`, `TenantScope`) or is a stateless grouping of static methods that belong together (`PasswordHelper`). A single loose function is still fine for a genuinely one-off, stateless calculation with nothing to group it with (`hashSeed` in `@helpers/random.helper`) — the bar is "does this belong with something else," not "must every function become a class."

**Exceptions where the ecosystem's own idiom wins over this preference — don't fight the framework:**

- **Elysia plugins** are composed instances, not classes: `export const HealthPlugin = new Elysia({ name: "health.plugin" }).get(...)`. Elysia's `.use()` chaining and type inference are built around this shape; wrapping a plugin in a class breaks the plugin composition Elysia expects.
- **Drizzle schema definitions** (`drizzle/elements/*.ts`) stay as the DSL's table/column builder calls (`pgSchema(...).table(...)`, `auth.table.withRLS(...)`) — this is declarative schema, not behavior, and the DSL only works as chained builder calls.
- **Zod schemas** (`source/cmd/secrets.ts`) stay as `z.object({...})` — same reasoning, it's a data shape declaration, not a place to group behavior.

## File naming

Every file under `source/` and `drizzle/customs/`, `drizzle/database/`, `drizzle/elements/` is named `<name>.<role>.ts` (or `.trg.sql` for triggers), where `<role>` names what the file *is* in the architecture, not just its content: `.plugin.ts` (an Elysia plugin), `.helper.ts` (a class or function grouping used across features), `.element.ts` (a Drizzle schema module), `.seeder.ts` (a seed data class), `.client.ts` (a shared client instance, e.g. `drizzler.client.ts`). A new file's role should be obvious from its name alone, without opening it.

## Path aliases, not relative chains

Use the declared aliases instead of relative imports across a boundary — `@secrets`, `@customs/*`, `@database/*`, `@elements/*` (data layer, `drizzle/`), and `@features/*`, `@security/*` (application code), `@helpers/*`, `@plugins/*` (infra, `source/infra/`). A relative import that climbs out of its own directory to reach one of these (`../../../infra/helpers/...`) should be the aliased form instead — see `coding.md` on why crossing a seam without its alias is a coupling smell.

## Config and environment

Environment variables are validated once, in `source/cmd/secrets.ts`, through a single `zod` schema parsed at import time (`envSchema.parse(process.env)`), with the inferred type exported alongside the parsed value (`export type Env = z.infer<typeof envSchema>`). Nothing else in the codebase reads `process.env` directly — every other module imports the already-validated `env` from `@secrets`, so an invalid or missing variable fails fast at boot instead of surfacing as an undefined value deep in a request handler.

## Data layer

- **Reuse the shared column/policy helpers** (`@customs/helpers/column.helper`, `@customs/helpers/policies.helper`) for repeated column patterns (`requiredTimestamp`, `optionalTimestamp`, `tenantId`) and RLS policies (`tenantIsolationPolicy`, `backupReadablePolicy`) instead of re-declaring the same `TIMESTAMPTZ`/`uuid`/policy boilerplate per table — see `database.md` for why every tenant-scoped table needs the same shape. A new table skipping the helper and hand-rolling the same columns is the shotgun-surgery smell from `coding.md` waiting to happen the next time the shared shape changes.
- **Tenant-scoped writes go through `TenantScope.run()`** (`@helpers/tenant.helper`), never an ad hoc `db.transaction(...)` that forgets to `SET LOCAL app.current_tenant_id`. `TenantScope` exists specifically so tenant context-setting isn't something every call site has to remember on its own — see `database.md` § Row-Level Security for why `SET LOCAL` inside the same transaction is the only safe way to do this under connection pooling.

## Constants over inline literals

Pull repeated or non-obvious literal values (weighted pools, catalogs, thresholds) into a named top-level `const` rather than inlining them where they're used — `TOOLS_CATALOG`, `EXECUTION_STATUS_POOL`, `DAY_MS` in `drizzle/customs/seeders/core.seeder.ts` are the existing pattern to follow. This is the magic-numbers smell from `coding.md` applied concretely here: a bare `24 * 60 * 60 * 1000` inline reads as noise, `DAY_MS` reads as intent.
