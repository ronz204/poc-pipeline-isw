# RESTful API — Spec

## Objective

Expose Swampert's business operations and reports as an HTTP API via ElysiaJS, organized as hexagonal architecture + DDD (`core` = domain, `feats` = HTTP adapter, `infra` = concrete adapters), so that the dashboard (`approach.md` §6, 15 pts) and the oral review's live demo (`approach.md` §8) have something to call. Every write operation reaches the database exclusively through the already-implemented PL/pgSQL procedures (`drizzle/customs/funcs/*.proc.sql`) — this layer orchestrates and validates HTTP concerns, it does not reimplement business logic or issue ad hoc `INSERT`/`UPDATE`/`DELETE` against domain tables. A request against a protected endpoint fails with `401` when its JWT is missing/invalid, and with the procedure's own `RAISE EXCEPTION` message (mapped to `4xx`) when the underlying PL/pgSQL call rejects the input — never with the request silently succeeding against the wrong tenant's data.

## Scope

**In scope — first pass, a prioritized subset over "every routine gets an endpoint" (explicit user choice):**

- One endpoint per procedure (5): `core.sp_launch_execution`, `core.sp_complete_execution`, `trace.sp_record_execution_step`, `core.sp_provision_swarm_roster`, `core.sp_archive_stale_swarms`.
- `reports.sp_refresh_reports(p_period date)` — triggers the recalculation the dashboard reads from.
- Read endpoints over the 3 `reports.*` tables (`monthly_execution_summary`, `swarm_task_summary`, `error_summary`) — plain `SELECT`s. This does not violate the "writes only through procedures" rule: these tables are read models with no independent write path of their own (`sp_refresh_reports` is the only thing that ever writes them), so reading them directly is the correct adapter, not a bypass.
- `trace.fn_table_history(p_table_name)` — the audit-history function `approach.md` §8.4 requires being able to demo live ("Consultar el historial de auditoría: quién cambió qué y cuándo").
- `POST /api/auth/login` — the one endpoint with no procedure behind it, since authentication isn't part of the procedural layer. Verifies against `auth.users` and issues a JWT.
- New top-level source layout: `source/cmd` (existing, composition root), `source/core` (new, domain), `source/feats` (new, HTTP adapter), `source/infra` (existing, gains two new subfolders — see **Technical context**).

**Explicitly deferred, confirmed with the user:**

- **The other 9 functions** (`fn_is_swarm_active`, `fn_next_attempt_number`, `fn_agent_belongs_to_swarm`, `fn_calculate_token_cost`, `fn_tenant_budget_threshold`, `fn_execution_total_cost`, `fn_stale_swarms`, `fn_tenant_active_agents`, `fn_execution_step_summary`) get no endpoint of their own in this pass. Each is already called internally by exactly one of the 5 procedures (`deltas/process.docs.md`'s call-graph table) — nothing in the dashboard or the oral-review script needs to call one directly. Revisit only if a concrete need surfaces later (e.g. the dashboard wants a standalone "is this swarm active" check).
- **The dashboard UI** (`projects/swampert-client`) — a separate slice; this one only has to give it something to fetch from.
- **RBAC enforcement beyond carrying identity.** The JWT carries `tenantId`/`userId`/`role`, but no endpoint in this pass rejects a call based on `role` — see **Risks**.
- **Pagination/filtering** beyond what a first pass needs (the reports reads take a `period`/`swarmId` filter where the underlying table is bucketed by one; nothing more elaborate).
- **Revoking `runner`'s direct table privileges**, or adding a DB-level guarantee that every write goes through a procedure — see **Risks**, this is enforced by this spec's convention and code review, not by grants.

## Technical context

**Routine catalog this slice calls** (verified against `drizzle/customs/funcs/*.sql`, cross-checked with `deltas/process.docs.md` and `deltas/reports.spec.md`):

| Routine | Schema | Kind | `SECURITY DEFINER` | `EXECUTE` granted to `runner` | Commits internally |
|---|---|---|---|---|---|
| `sp_launch_execution(p_task_id, p_max_attempts=3)` | `core` | procedure | yes (`sampler`) | yes (`20260814035712_granting_procedures`) | no |
| `sp_complete_execution(p_execution_id, p_status, p_max_attempts=3)` | `core` | procedure | yes | yes | no |
| `sp_record_execution_step(p_execution_id, p_agent_id, p_reasoning, p_tools_used, p_input_tokens, p_output_tokens, p_cost_per_1k_input, p_cost_per_1k_output)` | `trace` | procedure | yes | yes | no |
| `sp_provision_swarm_roster(p_swarm_id, p_agent_ids)` | `core` | procedure | yes | yes | no |
| `sp_archive_stale_swarms(p_inactive_since)` | `core` | procedure | **no** — runs as caller | yes | **yes, per swarm** |
| `sp_refresh_reports(p_period)` | `reports` | procedure | yes | yes (`20260814041704_granting_reports`) | no, but loops **every** tenant in one call |
| `fn_table_history(p_table_name)` | `trace` | function, returns table | n/a | PUBLIC default (no explicit grant found) | n/a |

The 9 domain-status enums a caller needs to pass or interpret, confirmed against `core.element.ts`: `core.swarm_status` (`active`/`paused`/`archived`), `core.task_status` (`pending`/`progress`/`completed`/`failed`), `core.execution_status` (`pending`/`running`/`completed`/`failed`).

**The calling-convention split — the single most important fact in this spec.** `source/infra/helpers/tenant.helper.ts`'s `TenantScope.run(tenantId, work)` wraps `work` in one `db.transaction()` and sets `app.current_tenant_id` via `set_config(..., true)` — transaction-local (`SET LOCAL` semantics), gone the instant that transaction ends. That's the right and sufficient calling path for the first 5 rows of the table above — they never end the caller's transaction. It is **not** usable for the last two:

- `sp_archive_stale_swarms` issues its own internal `COMMIT` per swarm. Calling it from inside `TenantScope.run()`'s open transaction fails outright — Postgres rejects transaction control from a routine invoked inside an already-open transaction the same way it rejects it inside `SECURITY DEFINER` (`deltas/process.spec.md` § Technical context already established the `SECURITY DEFINER`-side half of this rule). And because a `COMMIT` discards a transaction-local `set_config`, the tenant setting has to survive across it — `set_config(..., false)` (session-level, not transaction-scoped) on a connection that outlives the procedure's internal commits.
- `sp_refresh_reports` loops over **every** tenant inside its own body (`deltas/reports.spec.md` § Technical context). Pre-scoping it to one tenant via `TenantScope.run()` would be actively wrong — the procedure needs no caller-side tenant context at all.

Both need a call path outside `TenantScope.run()` — see **Implementation** for the concrete mechanism (a reserved connection, not the pooled one `TenantScope` uses).

**DB connection.** The app connects as `runner` (`POSTGRES_RUNNER_URL`/`USERNAME`/`PASSWORD` in `source/cmd/secrets.ts`, consumed by `drizzle/database/drizzler.client.ts` via `postgres-js` + `drizzle({ client })`). `runner` already holds direct table privileges on all 9 domain tables (the "current phase" concession `database.md` documents) plus the `EXECUTE` grants in the table above.

**Auth source.** `auth.users` (`drizzle/elements/auth.element.ts`): `id, tenantId, name, email, password (hash), role (admin/member/viewer), active, createdAt, deletedAt`, RLS-scoped, `unique(tenantId, email)` — email is unique **within** a tenant, not globally, so a bare email lookup at login time is ambiguous across tenants. `source/infra/helpers/password.helper.ts` already has `PasswordHelper.hash`/`.verify` via `Bun.password`. No JWT dependency exists in `package.json` yet.

**Alias resolution (user's explicit decision, overriding two options this spec's author proposed).** `tsconfig.json` currently declares `@features/*` → `source/app/features/*` and `@security/*` → `source/app/security/*`, both unused by any file in the repo. Resolution:

- Three new top-level aliases: `@cmd/*` → `source/cmd/*`, `@core/*` → `source/core/*`, `@feats/*` → `source/feats/*`.
- `infra` gets **no** blanket `@infra/*` alias — it keeps today's granular per-subfolder aliases (`@helpers/*`, `@plugins/*`) and gains new ones the same way as new subfolders are added under it. User's own words: *"en infra usaremos sub alias, helpers y plugins y los que vengan."*
- `@features/*` is dropped — superseded by `@feats/*`.
- `@security/*` is **repurposed**, not dropped: same alias name, repointed to a new `source/infra/security/*` (holding JWT sign/verify, alongside the existing `password.helper.ts`) instead of the never-built `source/app/security/*`. This reuses an already-reserved name for a real concern instead of leaving it orphaned.

**Core/feats split (user's explicit confirmation of classic ports & adapters).** `core` is pure domain — entities/types, port interfaces, use-cases that orchestrate a call to a PL/pgSQL routine through a port — zero Elysia/HTTP imports. `feats` is the HTTP adapter — one Elysia plugin per bounded context (`swarms`, `executions`, `reports`, `auth`), request/response validation via Elysia's own `t.Object(...)`, mapping HTTP in and out of a `core` use-case call. `infra` provides the concrete adapters implementing `core`'s ports — the actual Drizzle `sql` calls that `CALL`/`SELECT` the routines in the table above. This needs a new `infra` subfolder that doesn't exist yet.

**Existing Elysia wiring** (`source/cmd/service.ts`): `new Elysia({ prefix: "/api" })` with `OriginsPlugin` (CORS), `HealthPlugin` (`GET /health`), `ScalarsPlugin` (OpenAPI docs at `/docs` via `@elysia/openapi`) already `.use()`-chained. New `feats` plugins get `.use()`-chained onto the same instance, same pattern.

**Stale doc, not this slice's file to fix.** `deltas/process.docs.md` lines 3 and 90 still say the procedures' DCL "has not been applied yet... no migration" — that's stale; `20260814035712_granting_procedures` already applies it. Flagged here per `CLAUDE.md`'s "surface the mismatch, don't silently propagate it" rule, left for whoever next touches `process.docs.md`.

**`fn_table_history`'s `p_table_name` is a bare table name, not schema-qualified — discovered live, not obvious from the function's signature alone.** `trace.fn_table_history` does `WHERE a.entity_type = p_table_name`, and the audit triggers (`deltas/triggers.spec.md`) write `entity_type` as the bare table name (`'tasks'`, `'executions'`, `'swarms'`, `'users'` — verified directly against `trace.audit_log` on a live database), never schema-qualified. `GET /api/audit/core.tasks/history` silently returns `[]` (not a 404 — the function has nothing to reject, an unmatched name is just an empty result); the working call is `GET /api/audit/tasks/history`. This is the single easiest way to misuse this endpoint and read a false "no history" — worth remembering for the oral review demo (`approach.md` §8.4).

**Two raw-`sql`-template driver gotchas, found only by running every endpoint against a live Postgres — neither is a type error, both fail (or silently misbehave) only at runtime:**

- **A JS array interpolated into `drizzle-orm`'s `sql\`...\`` template does not become a Postgres array parameter.** `sql\`...${jsArray}...\`` executed via `.execute()` (the postgres-js driver path this slice uses for every `CALL`) hands the array straight to `postgres-js`'s low-level parameter bind, which — unlike `postgres-js`'s own tagged template — has no array serialization for that path: the driver sends the array's first/joined element as if it were a single scalar, and Postgres rejects it with `22P02 malformed array literal`. Fixed with a new `sqlArray()` helper (`source/infra/helpers/sql-array.helper.ts`) that builds an explicit `ARRAY[$1, $2, ...]` SQL fragment instead of interpolating the array directly — every array-typed procedure parameter (`p_agent_ids`, `p_tools_used`) goes through it.
- **A JS `Date` interpolated the same way throws at bind time, not at the database.** `postgres-js`'s low-level parameter serializer for `.unsafe()`-style execution (what `.execute()` uses) only accepts strings/Buffers/numbers — a raw `Date` object throws `TypeError: The "string" argument must be of type string or an instance of Buffer or ArrayBuffer. Received an instance of Date` before the query even reaches Postgres. Every `Date` bound this way needs `.toISOString()` (or `.toISOString().slice(0, 10)` for a `::date` cast) applied first. This does **not** affect Drizzle's query builder (`db.select().where(eq(column, dateValue))`) — that path has its own column-type codec and serializes `Date` correctly; the bug is specific to raw `sql\`` templates run through `.execute()`.

**`TenantScope.runDetached()`'s original design (`drizzle({ client: reserved })`) does not work — corrected after a live runtime failure, not caught by `tsc`.** A reserved connection off the pool (`this.db.$client.reserve()`) does not carry the same internal shape as the client `drizzle()` was originally built from — re-wrapping it in a fresh `drizzle({ client: reserved })` throws `undefined is not an object (evaluating 'client.options.parsers')` the first time it's used, entirely at runtime (both sides type-checked cleanly). The corrected design hands `work()` the raw, reserved `postgres-js` connection directly — a callable tagged-template function, not a `Drizzler` — so any query issued inside `runDetached()` uses `postgres-js`'s own template syntax (`reserved\`SELECT ...\``), not Drizzle's query builder or `sql` template. `source/infra/helpers/tenant.helper.ts` exports the inferred type as `ReservedConnection` (`Awaited<ReturnType<Drizzler["$client"]["reserve"]>>`) rather than importing a type name from `postgres`, so it can't drift from whatever `.reserve()` actually returns.

**`drizzle-orm` never throws the driver's `PostgresError` directly — every `.execute()` failure arrives wrapped in a `DrizzleQueryError`, with the real `PostgresError` one level down as `.cause`.** `error instanceof PostgresError` alone never matches in `ErrorsPlugin`'s `onError` handler; verified live that every `CALL` rejection needs `(error as { cause?: unknown }).cause instanceof PostgresError` checked as a fallback. Without this, every PL/pgSQL `RAISE EXCEPTION` — the exact mechanism the **Objective** describes as the source of `4xx` responses — fell through to a bare `500`.

## Implementation

Implemented and verified against a live Postgres (`services/postgres` via Docker) as of 2026-08-15 — every route below was exercised with real seeded data, not just type-checked. Two decisions below diverged from this section's original proposals after a live run exposed a runtime-only failure (`tsc` passed on both, cleanly, before the fix); each is called out where it happened, with the reasoning left in **Technical context** rather than a separate changelog, per this spec's living-document convention.

### 1. tsconfig.json

Added `@cmd/*`, `@core/*`, `@feats/*`; removed `@features/*`; repointed `@security/*` → `./source/infra/security/*`; added `@repos/*` → `./source/infra/repos/*`.

### 2. `source/infra` — two new subfolders

- `source/infra/security/jwt.plugin.ts` — **not** a `JwtHelper` class as originally proposed: `@elysia/jwt`'s `jwt()` returns a composed Elysia plugin whose `.sign()`/`.verify()` only exist on request context after `.use()`, the same "don't fight the framework" exception `engine.md` already carves out for Elysia plugins (`OriginsPlugin`, `HealthPlugin`) — wrapping it in a class would have nothing to wrap, there's no free-standing sign/verify to call outside a request.
- `source/infra/repos/*.repo.ts` — one class per bounded context (`auth`, `executions`, `swarms`, `reports`, `audit`) implementing a `core` port. Every procedure call goes through `TenantScope.run()` except the two below. Every array-typed procedure parameter goes through `sqlArray()` (see **Technical context**); every `Date` parameter is `.toISOString()`'d first.
- `source/infra/helpers/tenant.helper.ts`'s `TenantScope.runDetached(tenantId, work)` — the corrected design (see **Technical context** for why the original `drizzle({ client: reserved })` approach failed at runtime): reserves a connection off the pool (`this.db.$client.reserve()`), sets `app.current_tenant_id` at session level on it, hands `work()` that raw reserved connection (type `ReservedConnection`, exported from this file), then explicitly clears the setting and releases the connection back to the pool in a `finally`. Used only by `core.sp_archive_stale_swarms`'s repo method. `reports.sp_refresh_reports` needs no tenant step at all — it's called with a plain `this.db.execute(sql\`CALL reports.sp_refresh_reports(...)\`)` on the pooled connection, no reservation.

### 3. `source/core` — one folder per bounded context: `swarms`, `executions`, `reports`, `audit`, `auth`

Each holds `.port.ts` (interface the use-case depends on) and `.usecase.ts` (orchestration, no Elysia import) — the file-role suffixes proposed during specification, unchanged. E.g. `core/executions/launch-execution.usecase.ts` depends on a port implemented by `infra/repos/executions.repo.ts`.

### 4. `source/feats` — one Elysia plugin per bounded context

Routes, all mounted under `/api` in `service.ts` and verified live (see **How to test**):

| Method | Path | Backs |
|---|---|---|
| `POST` | `/api/auth/login` | login — see § Auth below |
| `POST` | `/api/executions/launch` | `sp_launch_execution` |
| `POST` | `/api/executions/:id/complete` | `sp_complete_execution` |
| `POST` | `/api/executions/:id/steps` | `sp_record_execution_step` |
| `POST` | `/api/swarms/:id/roster` | `sp_provision_swarm_roster` |
| `POST` | `/api/swarms/archive-stale` | `sp_archive_stale_swarms` |
| `POST` | `/api/reports/refresh` | `sp_refresh_reports` |
| `GET` | `/api/reports/monthly-executions` | `reports.monthly_execution_summary` read |
| `GET` | `/api/reports/swarm-tasks` | `reports.swarm_task_summary` read |
| `GET` | `/api/reports/errors` | `reports.error_summary` read |
| `GET` | `/api/audit/:table/history` | `fn_table_history` — `:table` is the **bare** table name (`tasks`, not `core.tasks`), see **Technical context** |

All except `/api/auth/login` require a valid JWT — `source/feats/shared/auth.guard.plugin.ts`'s `.resolve()` + `.onBeforeHandle()` decode it and reject with `401` before any handler runs; verified live that an unauthenticated call to a protected route never reaches the database. `source/feats/shared/errors.plugin.ts` is the global `PostgresError`/`DrizzleQueryError` → HTTP status mapper (see **Technical context**), mounted once in `service.ts` alongside the feature plugins.

### 5. Auth — login's tenant ambiguity, resolved

Because `email` is unique only within a tenant (`unique(tenantId, email)` on `auth.users`), `POST /api/auth/login` takes `{ tenantSlug, email, password }` — not email alone — and looks up `auth.tenants` by `slug` first to get `tenantId`, then `auth.users` by `(tenantId, email)`. `auth.tenants.slug` is already `unique()`, so this is a real, existing lookup key, not a new one. On success, issues a JWT with `{ tenantId, userId, role }`; on failure (unknown slug, unknown email within that tenant, wrong password, **or an inactive user** — `auth.users.active = false`, verified live against a seeded inactive admin), a uniform `401` — never distinguishing which reason applied, to avoid leaking which tenants/emails exist.

## Config / secrets

- `JWT_SECRET` (`source/cmd/secrets.ts`) — signing key for `@elysia/jwt`, required, no default (`z.string().min(32)`). Appended to `.env.sample`/`.env.local` with a placeholder value — replace the local one before deploying anywhere beyond this machine.
- `JWT_EXPIRES_IN` (`source/cmd/secrets.ts`) — token lifetime, defaults to `"1h"`.
- New dependency: `@elysia/jwt@^1.4.2` in `package.json` (matches the existing `@elysia/cors`/`@elysia/openapi` version line for this project's fork of the `elysia` plugin scope).
- No new Postgres role or grant needed — `runner`'s existing `EXECUTE` grants (table above) already cover every routine this slice calls; confirmed live, no grant errors on any call.

## Acceptance criteria

- [x] `source/core`, `source/feats` exist; `source/infra` gains `security/` and `repos/` only, existing files untouched.
- [x] `tsconfig.json` updated per **Implementation** § 1 (`@cmd`, `@core`, `@feats`, `@repos` added; `@features` removed; `@security` repointed).
- [x] One route per row of the **Implementation** § 4 table, mounted under the existing `/api` prefix in `service.ts`.
- [x] `POST /api/auth/login` issues a JWT from verified `auth.users` credentials; every other route rejects a missing/invalid JWT with `401` before doing any DB work — verified live (see **How to test**).
- [x] `sp_archive_stale_swarms` and `sp_refresh_reports` are called via the reserved-connection / plain-pooled path (**Implementation** § 2), never via `TenantScope.run()` — and verified not to leak tenant context to the next unrelated request (**How to test** step 4).
- [x] Every request/response validated with Elysia's `t.Object(...)`, matching the routine's real parameter/return shape from the **Technical context** table.
- [x] A `CALL`/`SELECT` issued through an endpoint produces the same row-level effect as calling the routine directly — verified for all 7 routines in the **Implementation** § 4 table against a live Postgres, not just one.

## How to test

Verified live against a real Postgres (`services/postgres`, `docker compose up`, then `bun run drizz:migrate && bun run drizz:seeding`) on 2026-08-15 — every step below was actually run, not just planned. Seeded users all share the password `swampert-dev-password` (`drizzle/customs/seeders/auth.seeder.ts`); pick an `active = true` row, since seeding randomizes `active` and an inactive user is a legitimate `401` (see **Risks**).

1. `bun run source/cmd/service.ts`, confirm `GET /api/health` → `200`. ✓
2. `POST /api/auth/login` with a seeded, active user's `{ tenantSlug, email, password }` → `200` with a JWT; an inactive user or wrong password → `401` with a uniform message. ✓
3. `POST /api/executions/launch` with a valid JWT and a seeded, non-completed `taskId` → `200` with the new execution row (`attemptNumber` incremented correctly on a task with prior attempts). Calling it again on the same task once it's `completed` → `400` (`check_violation`, the procedure's own "already completed" rejection); an unknown `taskId` → `404` (`no_data_found`). ✓
4. `POST /api/swarms/archive-stale` with an ancient `inactiveSince` → `{ archivedCount: 0 }`; with a recent one → `{ archivedCount: 1 }` against seed data, and the server stayed healthy afterward (`GET /api/health` still `200`). **The tenant-isolation check this step exists for**: logged in as a *different* tenant immediately after, its `GET /api/reports/swarm-tasks` showed only its own `tenant_id` (no cross-tenant leakage from the just-released reserved connection), and its own `archive-stale` call with the same cutoff correctly saw its own data, not the previous tenant's. ✓
5. `POST /api/reports/refresh` with a seeded period → `{ status: "accepted" }`; `GET /api/reports/monthly-executions` / `/swarm-tasks` / `/errors` afterward returned real aggregated rows matching what had just been written by the executions/tasks above (e.g. `executionCount: 1, avgDurationSeconds: "240.90"` for the execution launched and completed in step 3). ✓
6. `GET /api/audit/tasks/history` (bare name, see **Technical context**) after the task mutations in step 3 → the `created`/`updated` entries appear, each with a `before`/`after` snapshot and a human-readable `summary`, newest first. `GET /api/audit/core.tasks/history` (schema-qualified) returns `[]` — not a bug, see **Technical context**. ✓

## Risks / edge cases

1. **Pooled-connection tenant leakage was the single biggest way this slice could have been implemented wrong without erroring — verified closed, not just designed against.** `How to test` step 4 ran exactly this scenario live: `sp_archive_stale_swarms` for tenant A via the reserved connection, immediately followed by an unrelated login + read as tenant B. Tenant B saw only its own rows. Still the risk to re-check first if `runDetached()` is ever refactored — the reset-before-release in **Implementation** § 2 is 100% of what prevents this, and it's easy to remove by accident while "simplifying" the `finally` block.
2. **`sp_provision_swarm_roster`'s only feedback on partial success is a `RAISE NOTICE`, confirmed unrecoverable through this driver — not a hypothetical.** `postgres-js`'s `.execute()`/`.unsafe()` path (what every `CALL` in this slice uses) has no per-query hook for `NOTICE` messages; the chosen, implemented behavior is `POST /api/swarms/:id/roster` returning `{ swarmId, rosterSize }` — the roster's actual size after the call — rather than an added/skipped breakdown. A caller re-provisioning the same roster twice sees `rosterSize` stay flat and has to infer "nothing new was added" from that, not from an explicit count.
3. **No RBAC enforcement.** A `viewer`-role JWT can call a write endpoint exactly as freely as `admin` — the JWT carries `role` but nothing in this pass checks it per-route. Accepted for now given the project's academic scope; revisit if the oral review's audit/security questions (`approach.md` §8.4) push on it.
4. **`runner`'s direct table privileges mean nothing at the DB layer stops a future endpoint from bypassing procedures entirely** and running raw Drizzle CRUD against a domain table — the "writes only through procedures" rule is enforced by this spec and code review, not by a Postgres grant. Worth remembering the next time a new endpoint is added under time pressure.
5. **Uniform `401` on login hides which of {unknown tenant, unknown email, wrong password, inactive user} occurred, by design** — don't "fix" this later into distinct error messages without deciding that's actually wanted; it's a deliberate enumeration-resistance choice, not an oversight. The inactive-user case was found live (a seeded admin happened to be `active = false`) and folded into the same uniform rejection rather than treated as a separate case.
6. **`sp_archive_stale_swarms` runs as `runner`, not `sampler`** (the one procedure that does), so if `runner`'s direct table privileges are ever revoked in a future slice (`deltas/process.spec.md` § Scope already flags this as deferred), this is the one endpoint whose procedure needs an explicit re-grant on `core.swarms`/`core.tasks` to keep working — the other 6 routines this slice calls are unaffected since they're all `SECURITY DEFINER`.
7. **A JS array or `Date` bound through a raw `sql\`` template silently misbehaves or throws — always convert before interpolating.** See **Technical context** for the full detail; the short version for anyone adding a new repo method later: an array needs `sqlArray()`, a `Date` needs `.toISOString()`, and neither failure mode is a compile-time error — both were only caught by actually calling the endpoint against a live Postgres, exactly the kind of gap this spec's own "pending a live Postgres" caveat (carried by every other spec in this project) was hiding.
8. **A caught error's real Postgres error code lives at `error.cause`, not on the error itself.** Any future code that inspects a thrown error from a `.execute()` call (a new endpoint, a test, a log statement) needs to unwrap `DrizzleQueryError.cause` to reach the `PostgresError` — checking `error instanceof PostgresError` (or `error.code`) directly will silently never match. `source/feats/shared/errors.plugin.ts` is the one place this is already handled correctly; anywhere else that inspects a DB error needs the same unwrap.
