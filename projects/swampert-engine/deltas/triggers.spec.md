# Triggers & Audit — Spec

## Objective

Enforce business-rule integrity and maintain derived state on the core domain (`core.executions`, `core.tasks`, `core.swarm_agents`, `trace.execution_errors`) through triggers that fire automatically on INSERT/UPDATE/DELETE — never invoked manually — and, fully decoupled from those, an automatic audit system that records every change to the domain's main tables (`core.swarms`, `core.agents`, `core.tasks`, `core.executions`, `auth.users`) into `trace.audit_log`, queryable through `trace.fn_ver_historial_tabla`.

This is a retroactive spec: every trigger described here was implemented before this project adopted spec-driven development. The content below reflects what was verified against the actual code, not a plan for future work — except the one fix called out in **Implementation**, which was made during this spec's own investigation.

## Scope

**In scope:** the 5 source files under `drizzle/customs/triggers/` (`audit.trg.sql`, `executions.trg.sql`, `execution_errors.trg.sql`, `swarm_agents.trg.sql`, `tasks.trg.sql`), their mirrored custom migrations, and the query function `trace.fn_ver_historial_tabla`.

**Deliberately out of scope, confirmed with the user — not implemented here:**

- **Tenant-consistency validation for `trace.execution_errors`.** Unlike `core.swarm_agents` (which has `trg_swarm_agents_validate_tenant` precisely because it carries no `tenant_id` at all), `trace.execution_errors` *does* carry its own denormalized `tenant_id`, and no trigger cross-checks it against the `tenant_id` of the `core.executions` row it references via `execution_id`. Confirmed as a real gap, not fixed now — the same reasoning would apply to `trace.execution_steps`/`trace.token_costs` if this is ever addressed.
- **Automated trigger tests.** No `pgTAP` or `bun test` coverage exists for any of these triggers. The user explicitly chose to document the current manual-only verification flow (see **How to test**) as an accepted state, without committing to a specific point where automation gets added.
- **`auth.tenants` has no audit trigger.** Confirmed intentional: it's the root of multi-tenant isolation, and no human actor exists yet at the moment a tenant is created.
- **Revoking `runner`'s direct table privileges** in favor of `EXECUTE`-only access on `SECURITY DEFINER` procedures is already documented in `database.md` as a future migration tied to the procedures/functions milestone — a different slice, not this one.

## Technical context

- Triggers live across two schemas: `trace` (`fn_log_audit_change`, `fn_execution_errors_fail_execution`) and `core` (`fn_executions_*`, `fn_swarm_agents_validate_tenant`, `fn_tasks_validate_swarm_active`).
- The audit triggers are independent of the business triggers by design — stated explicitly in `audit.trg.sql`'s own header comment, matching `approach.md` §4 ("independiente de los triggers de negocio").
- `fn_log_audit_change` is `SECURITY INVOKER` (the Postgres default — none of these functions declare `SECURITY DEFINER`), so it runs with the privileges of whichever role performs the write. Today that's `runner`, which already has direct `SELECT`/`INSERT`/`UPDATE`/`DELETE` on all three schemas per the temporary concession documented in `database.md` § Postgres roles.
- Enum values used in trigger bodies were checked against `drizzle/elements/core.element.ts`: `swarm_status` (`active`/`paused`/`archived`) and `execution_status` (`pending`/`running`/`completed`/`failed`) match exactly.
- `core.swarm_agents` (`drizzle/elements/core.element.ts`) is confirmed to carry no `tenant_id` and no RLS (`core.table(...)`, not `core.table.withRLS(...)`) — this is exactly the isolation gap `trg_swarm_agents_validate_tenant` closes at the integrity level.
- `trace.audit_log.user_id` is `NOT NULL` with an `ON DELETE RESTRICT` FK to `auth.users(id)` (`drizzle/elements/trace.element.ts`) — this constraint is the center of the bug fixed during this spec (see **Implementation**).
- `TenantScope` (`source/infra/helpers/tenant.helper.ts`) splits tenant context into two separate calls: `TenantScope.run()` only sets `app.current_tenant_id`; `TenantScope.setActor()` sets `app.current_user_id` and is opt-in per call site. Today the only caller of `setActor()` is the seed runner (`drizzle/customs/seeders/seed.runnner.ts`), which invokes it before seeding `core`/`trace` data. No application endpoint calls `setActor()` yet, because the procedure layer that would perform business writes doesn't exist yet (see `approach.md`'s week 9-11 milestones).
- `approach.md` is still written in Spanish, per `CLAUDE.md`'s own note that this isn't the established language for new content — this spec cites its section numbers but restates requirements in English.

## Implementation

One real bug was found and fixed during this spec's investigation, in `trace.fn_log_audit_change` (`audit.trg.sql` and its mirrored migration `drizzle/migrations/20260731043017_modeling_audit/migration.sql`):

**The bug:** if a write to an audited table happened without `TenantScope.setActor()` having been called first, `v_actor` stayed `NULL` (from `current_setting('app.current_user_id', true)`), and the `INSERT INTO trace.audit_log` failed on the `user_id NOT NULL` constraint — aborting the entire triggering transaction, not just the audit write. Since no application code calls `setActor()` today (only the seeder does), any future write path that forgets to call it would silently break at the database layer.

**The fix (user's decision, reached via targeted questions):** the function was reordered to compute `v_tenant_id`/`v_entity_id`/`v_action`/`v_summary` from `TG_OP` first, then resolve the actor. If `v_actor` is still `NULL` after the pre-existing special case (a freshly-created user auditing itself, `TG_TABLE_NAME = 'users' AND TG_OP = 'INSERT'`), it now falls back to the tenant's admin user, or its oldest user if no admin exists — the same criterion the seeder already uses (`tenantUsers.find(u => u.role === 'admin') ?? tenantUsers[0]`):

```sql
SELECT id INTO v_actor
FROM auth.users
WHERE tenant_id = v_tenant_id
ORDER BY (role = 'admin') DESC, created_at ASC
LIMIT 1;
```

Both the canonical `.trg.sql` file and its mirrored migration were updated together. There is no `drizzle/migrations/meta/_journal.json` in this repo — meaning these migrations haven't been applied against any persistent database outside local dev yet — so the usual rule ("never rewrite an already-applied migration, add a new one instead") doesn't apply here: source and migration are the same in-progress change, not a historical one being revised.

## Acceptance criteria

- [x] At least 6 business triggers exist under `drizzle/customs/triggers/`, each fired by INSERT/UPDATE/DELETE and never invoked manually — satisfies `approach.md` §3 (12 pts). Current count: 6 (4 validation + 2 maintenance, see **Risks**).
- [x] `trace.audit_log` captures the modified table, operation type, user, exact timestamp, and a readable summary (not a full row dump) — satisfies `approach.md` §4 (10 pts).
- [x] Triggers on `swarms`/`agents`/`tasks`/`executions`/`users` write to `audit_log` automatically, including the no-actor-set case (fixed this session).
- [x] `trace.fn_ver_historial_tabla(nombre_tabla)` returns every recorded change for a given table, matching the `ver_historial_tabla` requirement in `approach.md` §4.
- [x] Every `.trg.sql` file has a mirrored custom migration with identical SQL — verified line-by-line for all 5 files this session.
- [ ] Per-trigger documentation (table, triggering event, exact behavior) — required as a submission deliverable (`TRIGGERS.md`/`AUDITORIA.md`, `approach.md` §7). Not this spec's responsibility, but this spec is the material that document should be derived from.

## How to test

No automated coverage exists yet (see **Scope**); verification today is manual.

1. From `projects/swampert-engine`, run `bun run drizz:seeding` — seeds tenants/users/swarms/etc. through `TenantScope` with `setActor()` invoked. Confirms the happy path (actor set) end to end, and populates `trace.audit_log` for every seeded `core.*` insert.
2. Manual `psql` checks, one per trigger:
   - `UPDATE core.executions SET status = 'running' WHERE status = 'completed'` → rejected: "No se puede transicionar la ejecución ... de estado terminal".
   - `INSERT INTO core.executions (..., attempt_number, ...)` with a number that isn't `count(*) + 1` for that task → rejected: "attempt_number inválido".
   - `INSERT INTO core.swarm_agents` with a `swarm_id`/`agent_id` pair from different tenants → rejected: "pertenecen a empresas distintas".
   - `INSERT INTO core.tasks` on a swarm with `status = 'archived'` (or `deleted_at IS NOT NULL`) → rejected accordingly.
   - `INSERT INTO trace.execution_errors` for a `running` execution → that execution flips to `failed` automatically.
   - `SELECT * FROM trace.fn_ver_historial_tabla('swarms')` → returns history ordered by `occurred_at DESC`.
3. Fix-specific check: inside a transaction, `SET LOCAL app.current_tenant_id` **without** setting `app.current_user_id`, then `UPDATE core.swarms ...` — confirm `trace.audit_log` gets a row attributed to the tenant's admin/oldest user, instead of the update failing on the `NOT NULL` constraint.

## Risks / edge cases

1. **Actor-fallback still depends on at least one user existing per tenant.** If a tenant somehow has zero rows in `auth.users`, the fallback finds nothing and the `audit_log` insert fails again. Accepted: nothing in the real flow creates business data for a tenant before at least one user exists.
2. **`execution_errors.tenant_id` isn't cross-validated** against the `tenant_id` of the execution it references (see **Scope**) — a caller could insert a mismatched `tenant_id` and no trigger would catch it.
3. **`trg_execution_errors_fail_execution` silently no-ops** (`UPDATE ... WHERE status NOT IN ('completed', 'failed')`, no `RAISE`) when the target execution is already terminal. Deliberate — avoids conflicting with `trg_executions_validate_transition` — but means an error inserted after an execution has already terminated leaves no trace in the execution's status, only in `execution_errors` itself.
4. **`fn_log_audit_change` strips `password`** from both before/after JSON snapshots (`to_jsonb(...) - 'password'`) — the only sensitive-column strip today, since `auth.users` is the only audited table with one. `to_jsonb` doesn't redact automatically: auditing a future table with its own sensitive column needs the same explicit strip added at that point.
5. **The rubric minimum is met exactly, not with margin.** `approach.md` §3 requires ≥6 triggers covering both roles (validation, derived-state maintenance). Current count is exactly 6: 4 validation (`trg_executions_validate_transition`, `trg_executions_validate_attempt_number`, `trg_swarm_agents_validate_tenant`, `trg_tasks_validate_swarm_active`) + 2 maintenance (`trg_executions_set_finished_at`, `trg_execution_errors_fail_execution`). Removing or merging any one without re-checking the count risks dropping below the graded minimum.
6. **`auth.tenants` staying outside `fn_log_audit_change` is a design decision**, not an oversight — don't add it "for consistency" without deciding that again; there's no human actor at tenant-creation time to attribute it to.
7. **No automated tests** means any regression in these triggers is only caught by the manual flow in **How to test** — there's no CI signal today.
