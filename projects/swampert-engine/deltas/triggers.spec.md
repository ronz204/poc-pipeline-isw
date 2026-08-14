# Triggers & Audit — Spec

## Objective

Enforce business-rule integrity and maintain derived state on the core domain (`core.executions`, `core.tasks`, `core.swarm_agents`, `trace.execution_errors`) through triggers that fire automatically on INSERT/UPDATE/DELETE — never invoked manually — and, fully decoupled from those, an automatic audit system that records every change to the domain's main tables (`core.swarms`, `core.agents`, `core.tasks`, `core.executions`, `auth.users`) into `trace.audit_log`, queryable through `trace.fn_table_history`.

This is a retroactive spec: every trigger described here was implemented before this project adopted spec-driven development. The content below reflects what was verified against the actual code, not a plan for future work — except the fixes called out in **Implementation** (the actor-fallback bug, and installing the audit system into a real migration), which were made during this spec's own investigation sessions.

## Scope

**In scope:** the 7 source files under `drizzle/customs/triggers/` — 6 business-trigger files, one per rule (`executions_validate_transition.trg.sql`, `executions_validate_attempt_number.trg.sql`, `executions_set_finished_at.trg.sql`, `swarm_agents_validate_tenant.trg.sql`, `tasks_validate_swarm_active.trg.sql`, `execution_errors_fail_execution.trg.sql`) plus `audit_log_changes.trg.sql` (the 5 audit triggers) — and the query function `trace.fn_table_history`.

**Migration status:** both groups are now mirrored into a migration.

- The **audit system** (`audit_log_changes.trg.sql`, `trace.fn_log_audit_change`, `trace.fn_table_history`) is mirrored into `drizzle/migrations/20260814032444_modeling_audit/migration.sql` — see **Implementation**, Session 2.
- The **6 business-trigger files** are mirrored into `drizzle/migrations/20260814034039_modeling_triggers/migration.sql` — see **Implementation**, Session 3.

Neither migration has been run against a live Postgres yet (see **Risks**) — both are statically verified only (`drizzle-kit check`), so "installed via migration" here means "wired into the migration chain," not "confirmed to apply cleanly."

**Deliberately out of scope, confirmed with the user — not implemented here:**

- **Tenant-consistency validation for `trace.execution_errors`.** Unlike `core.swarm_agents` (which has `trg_swarm_agents_validate_tenant` precisely because it carries no `tenant_id` at all), `trace.execution_errors` *does* carry its own denormalized `tenant_id`, and no trigger cross-checks it against the `tenant_id` of the `core.executions` row it references via `execution_id`. Confirmed as a real gap, not fixed now — the same reasoning would apply to `trace.execution_steps`/`trace.token_costs` if this is ever addressed.
- **Automated trigger tests.** No `pgTAP` or `bun test` coverage exists for any of these triggers. The user explicitly chose to document the current manual-only verification flow (see **How to test**) as an accepted state, without committing to a specific point where automation gets added.
- **`auth.tenants` has no audit trigger.** Confirmed intentional: it's the root of multi-tenant isolation, and no human actor exists yet at the moment a tenant is created.
- **Revoking `runner`'s direct table privileges** in favor of `EXECUTE`-only access on `SECURITY DEFINER` procedures is already documented in `database.md` as a future migration tied to the procedures/functions milestone — a different slice, not this one.

## Technical context

- Triggers live across two schemas: `trace` (`fn_log_audit_change`, `fn_execution_errors_fail_execution`) and `core` (`fn_executions_*`, `fn_swarm_agents_validate_tenant`, `fn_tasks_validate_swarm_active`).
- The audit triggers are independent of the business triggers by design — stated explicitly in `audit_log_changes.trg.sql`'s own header comment, matching `approach.md` §4 ("independiente de los triggers de negocio").
- `fn_log_audit_change` is `SECURITY INVOKER` (the Postgres default — none of these functions declare `SECURITY DEFINER`), so it runs with the privileges of whichever role performs the write. Today that's `runner`, which already has direct `SELECT`/`INSERT`/`UPDATE`/`DELETE` on all three schemas per the temporary concession documented in `database.md` § Postgres roles.
- Enum values used in trigger bodies were checked against `drizzle/elements/core.element.ts`: `swarm_status` (`active`/`paused`/`archived`) and `execution_status` (`pending`/`running`/`completed`/`failed`) match exactly.
- `core.swarm_agents` (`drizzle/elements/core.element.ts`) is confirmed to carry no `tenant_id` and no RLS (`core.table(...)`, not `core.table.withRLS(...)`) — this is exactly the isolation gap `trg_swarm_agents_validate_tenant` closes at the integrity level.
- `trace.audit_log.user_id` is `NOT NULL` with an `ON DELETE RESTRICT` FK to `auth.users(id)` (`drizzle/elements/trace.element.ts`) — this constraint is the center of the bug fixed during this spec (see **Implementation**).
- `TenantScope` (`source/infra/helpers/tenant.helper.ts`) splits tenant context into two separate calls: `TenantScope.run()` only sets `app.current_tenant_id`; `TenantScope.setActor()` sets `app.current_user_id` and is opt-in per call site. Today the only caller of `setActor()` is the seed runner (`drizzle/customs/seeders/seed.runnner.ts`), which invokes it before seeding `core`/`trace` data. No application endpoint calls `setActor()` yet, because the procedure layer that would perform business writes doesn't exist yet (see `approach.md`'s week 9-11 milestones).
- `approach.md` is still written in Spanish, per `CLAUDE.md`'s own note that this isn't the established language for new content — this spec cites its section numbers but restates requirements in English.

## Implementation

### Session 1 — actor-fallback bug

One real bug was found and fixed in `trace.fn_log_audit_change` (`audit_log_changes.trg.sql`, later mirrored into the migration described below):

**The bug:** if a write to an audited table happened without `TenantScope.setActor()` having been called first, `v_actor` stayed `NULL` (from `current_setting('app.current_user_id', true)`), and the `INSERT INTO trace.audit_log` failed on the `user_id NOT NULL` constraint — aborting the entire triggering transaction, not just the audit write. Since no application code calls `setActor()` today (only the seeder does), any future write path that forgets to call it would silently break at the database layer.

**The fix:** the function was reordered to compute `v_tenant_id`/`v_entity_id`/`v_action`/`v_summary` from `TG_OP` first, then resolve the actor. If `v_actor` is still `NULL` after the pre-existing special case (a freshly-created user auditing itself, `TG_TABLE_NAME = 'users' AND TG_OP = 'INSERT'`), it now falls back to the tenant's admin user, or its oldest user if no admin exists — the same criterion the seeder already uses (`tenantUsers.find(u => u.role === 'admin') ?? tenantUsers[0]`):

```sql
SELECT id INTO v_actor
FROM auth.users
WHERE tenant_id = v_tenant_id
ORDER BY (role = 'admin') DESC, created_at ASC
LIMIT 1;
```

### Session 2 — installing the audit system into a real migration

Until this session, `trace.audit_log` (the table) existed in the schema (`drizzle/migrations/20260730045542_modeling_trace/`), but nothing installed `trace.fn_log_audit_change`, `trace.fn_table_history`, or the 5 `trg_audit_*` triggers into any migration — grepping every `migration.sql` in the repo for `CREATE TRIGGER`/`CREATE FUNCTION`/`CREATE PROCEDURE` returned nothing. A database built from migrations alone would have had an audit table with nothing ever writing to it.

**This reverses an earlier, deliberate decision — worth knowing before touching this again.** On 2026-08-03, commits `69db2bc`/`caafc7c` deleted a prior mirrored-migration for this exact audit system (`20260731043017_modeling_audit`, `20260731043051_granting_audit`) and moved to hand-applied-only `drizzle/customs/` files specifically to avoid duplicating the same SQL in two places — documented in full in `deltas/process.spec.md` § Implementation § Migration, which covers this same reversal and its rationale (a hand-applied-only model means `drizzle-kit migrate` alone never produces a working audit trail or triggers) in more detail than is repeated here.

The user scaffolded `drizzle/migrations/20260814032444_modeling_audit/` (via drizzle-kit, so `snapshot.json` was already correct — identical `ddl` to the prior snapshot, just a new `id`/`prevIds` link in the chain), and `migration.sql` was filled in to mirror, statement for statement, the three canonical source files in this order: `trace.fn_log_audit_change()`, `trace.fn_table_history(p_table_name)`, then the 5 `CREATE TRIGGER` statements (`trg_audit_swarms`, `trg_audit_agents`, `trg_audit_tasks`, `trg_audit_executions`, `trg_audit_users`), separated by `--> statement-breakpoint` markers to match this repo's existing custom-migration convention (see `20260730045547_granting_trace/migration.sql`).

No granting migration was needed: `fn_log_audit_change` and `fn_table_history` are `SECURITY INVOKER` (the default), so they run as `runner`, which already has `INSERT`/`UPDATE`/`DELETE` on `trace.*` from the existing `granting_trace` migration; and Postgres grants `EXECUTE` on new `plpgsql` functions to `PUBLIC` by default, so no explicit `GRANT EXECUTE` was required either.

**Verification performed:** `bunx --bun drizzle-kit check` confirms the new migration's snapshot chain is internally consistent (no orphaned `id`/`prevIds`, no drift between generated and on-disk snapshots). **Not verified:** an actual `drizzle-kit migrate` run against a live Postgres — Docker was not running in this environment and no `services/compose.yml` exists despite `.claude/CLAUDE.md` referencing one (a separate, pre-existing doc/reality gap, not something addressed here). `check` proves the migration is wired into the chain correctly; it does not prove the SQL applies cleanly to a real database. Do that verification (see **How to test**) before relying on this as done for the oral review.

### Session 3 — installing the 6 business triggers into a real migration

Same gap, same fix. The user scaffolded `drizzle/migrations/20260814034039_modeling_triggers/` (snapshot chain already correct — `prevIds` points at `20260814032444_modeling_audit`'s id), and `migration.sql` was filled in to mirror, statement for statement, the 6 canonical source files in **Scope**'s order: for each, its `CREATE OR REPLACE FUNCTION` immediately followed by its `CREATE TRIGGER`, each separated by `--> statement-breakpoint`, matching the convention established in the audit migration.

No granting migration was needed for the same reason as Session 2: none of these 6 functions declare `SECURITY DEFINER`, so they run `SECURITY INVOKER` as `runner`, which already has direct `SELECT`/`INSERT`/`UPDATE`/`DELETE` on `core.*`/`trace.*` per the "current phase" concession in `database.md` § Postgres roles; `EXECUTE` on the new functions is implicitly granted to `PUBLIC` by Postgres's default.

**Verification performed:** `bunx --bun drizzle-kit check` after this migration was added — chain still consistent. **Not verified:** applying it to a live database, for the same environment reason as Session 2 (no Docker/Postgres available). The trigger *firing order* between `trg_executions_set_finished_at` and `trg_executions_validate_transition` (both `BEFORE UPDATE` on `core.executions`) is determined by Postgres alphabetically by trigger name at fire time, not by the order either `CREATE TRIGGER` statement appears in this migration — `set_finished_at` fires before `validate_transition` ('s' < 'v'), so a terminal-status update gets `finished_at` stamped first, then validated as `>= started_at`. This ordering already existed implicitly in the separate source files; nothing about mirroring them into one migration file changes it.

## Acceptance criteria

- [x] At least 6 business triggers exist under `drizzle/customs/triggers/`, each fired by INSERT/UPDATE/DELETE and never invoked manually — satisfies `approach.md` §3's trigger design (12 pts). Current count: 6 (4 validation + 2 maintenance, see **Risks**).
- [x] Those 6 business triggers are installed via a migration (`drizzle/migrations/20260814034039_modeling_triggers/migration.sql`, Session 3). Statically verified via `bunx --bun drizzle-kit check`; not yet run against a live database (see **Risks**).
- [x] `trace.audit_log` captures the modified table, operation type, user, exact timestamp, and a readable summary (not a full row dump) — satisfies `approach.md` §4's table design (10 pts).
- [x] The 5 `trg_audit_*` triggers and `trace.fn_log_audit_change` are installed via a migration (`drizzle/migrations/20260814032444_modeling_audit/migration.sql`), including the no-actor-set fallback case (fixed Session 1). Statically verified via `bunx --bun drizzle-kit check`; not yet run against a live database (see **Implementation**, **How to test**).
- [x] `trace.fn_table_history(p_table_name)` returns every recorded change for a given table, matching the `ver_historial_tabla` requirement in `approach.md` §4, and is installed via the same migration.
- [ ] Per-trigger documentation (table, triggering event, exact behavior) — required as a submission deliverable (`TRIGGERS.md`/`AUDITORIA.md`, `approach.md` §7). Not this spec's responsibility, but this spec is the material that document should be derived from.

## How to test

No automated coverage exists yet (see **Scope**); verification today is manual, and requires a live Postgres — none was available in the environment this spec was last updated from.

0. `bunx --bun drizzle-kit check` (from `projects/swampert-engine`) — static, no live database needed. Confirms the migration snapshot chain is consistent; does **not** confirm the SQL applies. Run this after any edit to a migration file, before attempting a real `migrate`.
1. `bunx --bun drizzle-kit migrate` against a real Postgres, then `bun run drizz:seeding` — seeds tenants/users/swarms/etc. through `TenantScope` with `setActor()` invoked. Confirms both new migrations actually apply, then confirms the happy path (actor set) end to end, populating `trace.audit_log` for every seeded `core.*` insert. **This has not been run yet in any environment** — see **Risks**.
2. Manual `psql` checks, one per trigger:
   - `UPDATE core.executions SET status = 'running' WHERE status = 'completed'` → rejected: "No se puede transicionar la ejecución ... de estado terminal".
   - `INSERT INTO core.executions (..., attempt_number, ...)` with a number that isn't `count(*) + 1` for that task → rejected: "attempt_number inválido".
   - `INSERT INTO core.swarm_agents` with a `swarm_id`/`agent_id` pair from different tenants → rejected: "pertenecen a empresas distintas".
   - `INSERT INTO core.tasks` on a swarm with `status = 'archived'` (or `deleted_at IS NOT NULL`) → rejected accordingly.
   - `INSERT INTO trace.execution_errors` for a `running` execution → that execution flips to `failed` automatically.
   - `SELECT * FROM trace.fn_table_history('swarms')` → returns history ordered by `occurred_at DESC`.
3. Fix-specific check: inside a transaction, `SET LOCAL app.current_tenant_id` **without** setting `app.current_user_id`, then `UPDATE core.swarms ...` — confirm `trace.audit_log` gets a row attributed to the tenant's admin/oldest user, instead of the update failing on the `NOT NULL` constraint.

## Risks / edge cases

1. **Actor-fallback still depends on at least one user existing per tenant.** If a tenant somehow has zero rows in `auth.users`, the fallback finds nothing and the `audit_log` insert fails again. Accepted: nothing in the real flow creates business data for a tenant before at least one user exists.
2. **`execution_errors.tenant_id` isn't cross-validated** against the `tenant_id` of the execution it references (see **Scope**) — a caller could insert a mismatched `tenant_id` and no trigger would catch it.
3. **`trg_execution_errors_fail_execution` silently no-ops** (`UPDATE ... WHERE status NOT IN ('completed', 'failed')`, no `RAISE`) when the target execution is already terminal. Deliberate — avoids conflicting with `trg_executions_validate_transition` — but means an error inserted after an execution has already terminated leaves no trace in the execution's status, only in `execution_errors` itself.
4. **`fn_log_audit_change` strips `password`** from both before/after JSON snapshots (`to_jsonb(...) - 'password'`) — the only sensitive-column strip today, since `auth.users` is the only audited table with one. `to_jsonb` doesn't redact automatically: auditing a future table with its own sensitive column needs the same explicit strip added at that point.
5. **The rubric minimum is met exactly, not with margin.** `approach.md` §3 requires ≥6 triggers covering both roles (validation, derived-state maintenance). Current count is exactly 6: 4 validation (`trg_executions_validate_transition`, `trg_executions_validate_attempt_number`, `trg_swarm_agents_validate_tenant`, `trg_tasks_validate_swarm_active`) + 2 maintenance (`trg_executions_set_finished_at`, `trg_execution_errors_fail_execution`). Removing or merging any one without re-checking the count risks dropping below the graded minimum.
6. **`auth.tenants` staying outside `fn_log_audit_change` is a design decision**, not an oversight — don't add it "for consistency" without deciding that again; there's no human actor at tenant-creation time to attribute it to.
7. **No automated tests** means any regression in these triggers is only caught by the manual flow in **How to test** — there's no CI signal today.
8. **Neither `20260814032444_modeling_audit` nor `20260814034039_modeling_triggers` has been run against a live database.** No Docker/Postgres was available in the environment they were written in, so both are only verified statically (`bunx --bun drizzle-kit check` — chain consistency, not SQL correctness) and by manual review against the canonical source files. Run `drizzle-kit migrate` for real, then the manual checks in **How to test**, before treating `approach.md` §3 or §4 as done for the oral review. This is the single biggest remaining risk in this spec — everything else here describes SQL that's been reviewed but never executed against Postgres.
9. **The audit/trigger SQL now exists in two places that must be kept byte-identical by hand** — `drizzle/customs/{triggers,funcs}/*.sql` (canonical, documented source) and its migration mirror. Nothing in this repo's tooling generates one from the other or diffs them; editing a trigger or function body means remembering to edit both files. This is the direct, accepted cost of reversing the 2026-08-03 decision — see **Implementation**, Session 2 — and it's the same risk `deltas/process.spec.md` now carries for the functions migration.
10. **Same-table `BEFORE UPDATE` trigger firing order is implicit, not declared.** `trg_executions_set_finished_at` and `trg_executions_validate_transition` both fire on `core.executions` `BEFORE UPDATE`; Postgres orders same-event triggers alphabetically by name, not by migration statement order, so `set_finished_at` ('s') always runs before `validate_transition` ('v') — see **Implementation**, Session 3. If either trigger is ever renamed, re-check this ordering assumption; nothing enforces it explicitly (e.g. no `CREATE TRIGGER ... AFTER trg_x` dependency exists in Postgres for `BEFORE` triggers).
