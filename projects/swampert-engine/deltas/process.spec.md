# Business Procedures & Functions — Spec

## Objective

Automate the swarm/task/execution business lifecycle as 5 `SECURITY DEFINER` stored procedures — launching an execution attempt, closing one (with automatic retry), recording an execution step and its cost, provisioning a swarm's agent roster, and archiving stale swarms — each backed by reusable functions, so that a single `CALL` replaces what today would require several hand-run, unvalidated statements. Every procedure validates its inputs and fails with a declared exception instead of letting an invalid state persist; every procedure touching more than one table wraps its writes in an explicit transaction. This satisfies `approach.md` §1 (Procedimientos, 18 pts) and §2 (Funciones, 15 pts).

## Scope

**In scope:**

- 5 procedures: `core.sp_launch_execution`, `core.sp_complete_execution`, `trace.sp_record_execution_step`, `core.sp_provision_swarm_roster`, `core.sp_archive_stale_swarms`.
- 9 functions (6 scalar, 3 table-returning) — see **Implementation**.
- One new migration pair (`NNNN_modeling_procedures` / `NNNN_granting_procedures`) that creates these objects, adds `FORCE ROW LEVEL SECURITY` on the 9 tenant-scoped tables, and grants `EXECUTE` on the 5 procedures to `runner`.
- `.proc.sql` files under `drizzle/customs/funcs/` (see **Technical context** for why this directory, not a new `procs/`).

**Deliberately out of scope, confirmed with the user:**

- **Physical purge.** No procedure issues a `DELETE`. Every destructive-sounding process (swarm going stale, an execution exhausting its retries) resolves as a status transition (`archived`, `failed`) or the existing `deleted_at` soft-delete column — never a row physically removed. A hard-delete retention procedure was considered and explicitly rejected as too risky to demo live in the oral review.
- **Refactoring `trg_executions_validate_attempt_number` to reuse `core.fn_next_attempt_number`.** The trigger keeps its own inline `count(*) + 1` query. The new function duplicates that logic for `sp_launch_execution`'s own use. This is accepted duplication (see **Risks**), not an oversight — touching an already-shipped, spec'd trigger (`deltas/triggers.spec.md`) is a different slice.
- **Revoking `runner`'s direct table privileges.** `database.md` documents the eventual plan (`SECURITY DEFINER` procedures replace direct writes, `runner` ends up with `SELECT` + `EXECUTE` only) but the user explicitly confirmed this slice is additive only: `runner` keeps every privilege it has today, and only gains `EXECUTE` on the 5 new procedures. Verified today that `projects/swampert-engine/source/` contains no `.insert()`/`.update()`/`.delete()` call at all, so nothing currently depends on direct writes — but the revocation itself is left for a future slice, not bundled here.
- **Automated tests.** Same accepted state as `deltas/triggers.spec.md` — no `pgTAP`/`bun test` coverage exists yet for any procedure or function; verification is manual (see **How to test**).
- **Summary tables and the dashboard.** Separate rubric components (`approach.md` §5–6), not this slice's job, even though `sp_complete_execution` and `sp_record_execution_step` are exactly the writes those summary tables will eventually aggregate.

## Technical context

- Domain model verified against `drizzle/elements/{auth,core,trace,roles}.element.ts`. Relevant chains: `core.tasks.swarm_id → core.swarms.id`, `core.executions.task_id → core.tasks.id`, `trace.execution_steps.{execution_id, agent_id}`, `trace.token_costs.{execution_id, step_id}`. `core.swarm_agents` is a pure junction table (composite PK, no `tenant_id`, no RLS) already protected by `trg_swarm_agents_validate_tenant` (`deltas/triggers.spec.md`).
- Enums used by the new procedures/functions, confirmed against `core.element.ts`/`auth.element.ts`: `core.swarm_status` (`active`/`paused`/`archived`), `core.task_status` (`pending`/`progress`/`completed`/`failed`), `core.execution_status` (`pending`/`running`/`completed`/`failed`), `auth.tenant_plan` (`basic`/`pro`/`enterprise`).
- **Existing triggers this slice must not fight.** `trg_executions_validate_transition` already rejects reopening a terminal execution and any `finished_at < started_at`; `trg_executions_validate_attempt_number` already rejects a non-consecutive `attempt_number` on `INSERT`; `trg_tasks_validate_swarm_active` already rejects creating a task on an archived/soft-deleted swarm. The new procedures validate the same conditions *before* attempting the write (so the caller gets a clear, procedure-level exception instead of relying on the trigger to reject it), but the triggers remain the last line of defense regardless of which code path writes the row.
- **File placement.** `engine.md` establishes `.trg.sql` for triggers and (implicitly, via the 2 existing files) `.fn.sql` for functions, both flat inside `drizzle/customs/<kind>/`. The user chose to keep procedures in the same directory as functions (`drizzle/customs/funcs/`) rather than a new `drizzle/customs/procs/`, differentiated by extension (`.proc.sql` vs `.fn.sql`) and SQL name prefix (`sp_` vs `fn_`) — one less top-level directory, and procedures/functions are already closely related (every procedure calls at least one function).
- **`SECURITY DEFINER` and RLS.** `database.md` § Postgres roles already names this exact milestone as the trigger for two follow-ups: procedures owned by `sampler` need `FORCE ROW LEVEL SECURITY` on every tenant-scoped table (today only `ENABLE`), because otherwise `sampler`-as-owner would bypass `tenant_isolation` while executing the procedure body; and `runner` needs `EXECUTE` on the procedures to call them at all. Both are folded into this slice's migration (see **Implementation**) — `FORCE` is not optional once these procedures exist, it's what keeps them from silently defeating multi-tenant isolation the moment they run.
- `engine.md`'s "classes over standalone functions" convention is TypeScript-specific and doesn't apply here — `.proc.sql`/`.fn.sql` are raw SQL artifacts owned by Postgres, the same reasoning that already keeps `.trg.sql` files as plain SQL rather than wrapped in application code.
- `approach.md` is in Spanish; this spec (like `deltas/triggers.spec.md`) restates its requirements in English to match this project's established `.claude/docs/`/`deltas/*.md` language.

## Implementation

### Procedures

**1. `core.sp_launch_execution(p_task_id uuid, p_max_attempts integer DEFAULT 3)`**
Starts a new execution attempt for a task.
- Validates: task exists and isn't soft-deleted; `core.fn_is_swarm_active(swarm_id)` is true for the task's swarm; task isn't already `completed`.
- `v_attempt := core.fn_next_attempt_number(p_task_id)`.
- `INSERT INTO core.executions (..., attempt_number, status, started_at) VALUES (..., v_attempt, 'pending', now())`.
- `IF` the task's current status is `pending` `THEN` update it to `progress` — `ELSE` leave it (already `progress` from a prior attempt).
- Touches `core.executions` + `core.tasks` → explicit `BEGIN`/`COMMIT`, `EXCEPTION WHEN OTHERS THEN ROLLBACK; RAISE;`.

**2. `core.sp_complete_execution(p_execution_id uuid, p_status core.execution_status, p_max_attempts integer DEFAULT 3)`**
Closes an execution, with automatic retry on failure.
- Validates: execution exists and its current status isn't already `completed`/`failed`; `p_status` is exactly `'completed'` or `'failed'` (`ELSE RAISE EXCEPTION`); if `p_status = 'completed'`, at least one row comes back from `trace.fn_execution_step_summary(p_execution_id)` — an execution can't be marked done with zero recorded work.
- `UPDATE core.executions SET status = p_status, finished_at = now() WHERE id = p_execution_id`.
- `CASE p_status`:
  - `WHEN 'completed'` → `UPDATE core.tasks SET status = 'completed' WHERE id = v_task_id`.
  - `WHEN 'failed'` → `IF v_attempt_number < p_max_attempts THEN CALL core.sp_launch_execution(v_task_id, p_max_attempts); ELSE UPDATE core.tasks SET status = 'failed' ...; END IF`.
- Touches `core.executions` + `core.tasks` (plus, on retry, whatever `sp_launch_execution` itself writes) → explicit transaction.

**3. `trace.sp_record_execution_step(p_execution_id uuid, p_agent_id uuid, p_reasoning jsonb, p_tools_used text[], p_input_tokens integer, p_output_tokens integer, p_cost_per_1k_input numeric, p_cost_per_1k_output numeric)`**
Records one execution step together with its token cost.
- Resolves `v_swarm_id`/`v_tenant_id` with a direct `execution → task → swarm` join (no dedicated function — a one-line join doesn't earn its own reusable unit).
- Validates: execution exists and its status isn't terminal; `core.fn_agent_belongs_to_swarm(p_agent_id, v_swarm_id)` is true.
- `v_cost := trace.fn_calculate_token_cost(p_input_tokens, p_output_tokens, p_cost_per_1k_input, p_cost_per_1k_output)`.
- `IF trace.fn_execution_total_cost(p_execution_id) + v_cost > core.fn_tenant_budget_threshold(v_tenant_id) THEN RAISE EXCEPTION` — blocks before either insert happens.
- `INSERT INTO trace.execution_steps (...)`, then `INSERT INTO trace.token_costs (..., estimated_cost)`.
- Touches `trace.execution_steps` + `trace.token_costs` → explicit transaction; the budget check happening before either `INSERT` means a rejected step never partially lands.

**4. `core.sp_provision_swarm_roster(p_swarm_id uuid, p_agent_ids uuid[])`**
Assigns a batch of agents to a swarm.
- Validates: swarm exists, is active, isn't soft-deleted.
- `FOR v_agent_id IN SELECT unnest(p_agent_ids) LOOP`: skip any id not present in `core.fn_tenant_active_agents(v_tenant_id)` (wrong tenant or inactive); `IF NOT EXISTS (SELECT 1 FROM core.swarm_agents WHERE swarm_id = p_swarm_id AND agent_id = v_agent_id) THEN INSERT ... END IF`.
- Single table (`core.swarm_agents`) touched across all iterations — no explicit multi-table transaction needed; `approach.md`'s transaction requirement is conditional on ">1 table" and genuinely doesn't apply here.

**5. `core.sp_archive_stale_swarms(p_inactive_since timestamptz)`**
Batch job: archives swarms with no recent activity.
- Opens a cursor over `core.fn_stale_swarms(p_inactive_since)` (active swarms with no task created after `p_inactive_since` and no non-terminal execution).
- `WHILE` fetching a row: `UPDATE core.swarms SET status = 'archived' WHERE id = v_row.swarm_id`; `UPDATE core.tasks SET status = 'failed' WHERE swarm_id = v_row.swarm_id AND status IN ('pending', 'progress')`; then `COMMIT` before fetching the next row.
- Touches `core.swarms` + `core.tasks`, committed per swarm inside the loop — the one place a `COMMIT` happens mid-procedure, which only a `PROCEDURE` (not a `FUNCTION`) can do in Postgres. Deliberately non-atomic across swarms (see **Risks**).

### Functions

| Function | Kind | Returns | Called by |
|---|---|---|---|
| `core.fn_is_swarm_active(p_swarm_id uuid)` | Scalar | `boolean` | `sp_launch_execution`, `sp_provision_swarm_roster` |
| `core.fn_next_attempt_number(p_task_id uuid)` | Scalar | `integer` | `sp_launch_execution` |
| `core.fn_agent_belongs_to_swarm(p_agent_id uuid, p_swarm_id uuid)` | Scalar | `boolean` | `sp_record_execution_step` |
| `trace.fn_calculate_token_cost(p_input_tokens integer, p_output_tokens integer, p_cost_per_1k_input numeric, p_cost_per_1k_output numeric)` | Scalar | `numeric` | `sp_record_execution_step` |
| `core.fn_tenant_budget_threshold(p_tenant_id uuid)` | Scalar | `numeric` | `sp_record_execution_step` |
| `trace.fn_execution_total_cost(p_execution_id uuid)` | Scalar | `numeric` | `sp_record_execution_step` |
| `core.fn_stale_swarms(p_inactive_since timestamptz)` | Table | `TABLE(swarm_id uuid, tenant_id uuid, last_task_at timestamptz)` | `sp_archive_stale_swarms` |
| `core.fn_tenant_active_agents(p_tenant_id uuid)` | Table | `TABLE(agent_id uuid, name text, role text)` | `sp_provision_swarm_roster` |
| `trace.fn_execution_step_summary(p_execution_id uuid)` | Table | `TABLE(step_number integer, agent_id uuid, tools_used text[], occurred_at timestamptz)` | `sp_complete_execution` |

`core.fn_tenant_budget_threshold` is the one function whose body is a `CASE` on `auth.tenants.plan`:

```sql
CASE p_plan
  WHEN 'basic'      THEN 50.00
  WHEN 'pro'         THEN 250.00
  WHEN 'enterprise' THEN 1000.00
END
```

These three numbers are illustrative placeholders, not a requirement derived from `approach.md` or any real pricing decision — `approach.md` requires reusing the data model without structural changes, so there is no `budget_limit` column to read instead. See **Risks**.

### Migration

A new `NNNN_modeling_procedures` / `NNNN_granting_procedures` pair (same modeling/DCL split as every existing migration, `database.md` § Migrations):

- **Modeling:** the 5 `.proc.sql` files and 9 `.fn.sql` files, each `CREATE OR REPLACE`, procedures declared `SECURITY DEFINER`.
- **Granting:**
  ```sql
  ALTER TABLE auth.users FORCE ROW LEVEL SECURITY;
  ALTER TABLE core.swarms FORCE ROW LEVEL SECURITY;
  ALTER TABLE core.agents FORCE ROW LEVEL SECURITY;
  ALTER TABLE core.tasks FORCE ROW LEVEL SECURITY;
  ALTER TABLE core.executions FORCE ROW LEVEL SECURITY;
  ALTER TABLE trace.execution_steps FORCE ROW LEVEL SECURITY;
  ALTER TABLE trace.token_costs FORCE ROW LEVEL SECURITY;
  ALTER TABLE trace.execution_errors FORCE ROW LEVEL SECURITY;
  ALTER TABLE trace.audit_log FORCE ROW LEVEL SECURITY;

  GRANT EXECUTE ON PROCEDURE core.sp_launch_execution, core.sp_complete_execution,
    trace.sp_record_execution_step, core.sp_provision_swarm_roster,
    core.sp_archive_stale_swarms TO runner;
  ```
  No `REVOKE` statement — `runner` keeps every direct table privilege it has today (see **Scope**).

## Acceptance criteria

- [ ] At least 5 procedures exist, each automating a real multi-step process (not a trivial single-table write) — `approach.md` §1. Current design: 5 (`sp_launch_execution`, `sp_complete_execution`, `sp_record_execution_step`, `sp_provision_swarm_roster`, `sp_archive_stale_swarms`).
- [ ] Across the 5 procedures, `IF/ELSE`, `CASE`, `FOR`, and `WHILE` each appear at least once — `approach.md` §1. Mapping: `IF/ELSE` in `sp_launch_execution`/`sp_complete_execution`/`sp_record_execution_step`; `CASE` in `sp_complete_execution`; `FOR` in `sp_provision_swarm_roster`; `WHILE` in `sp_archive_stale_swarms`.
- [ ] Every procedure receives real parameters (ids, quantities, dates) and validates them, raising a declared exception on invalid input — no hardcoded values — `approach.md` §1.
- [ ] Every procedure that writes to more than one table wraps those writes in an explicit `BEGIN`/`COMMIT`/`ROLLBACK` — `approach.md` §1. Applies to all 5 except `sp_provision_swarm_roster` (single table, documented as not applicable).
- [ ] At least 8 functions exist, each used by at least one of the 5 procedures — `approach.md` §2. Current design: 9 (`fn_is_swarm_active`, `fn_next_attempt_number`, `fn_agent_belongs_to_swarm`, `fn_calculate_token_cost`, `fn_tenant_budget_threshold`, `fn_execution_total_cost`, `fn_stale_swarms`, `fn_tenant_active_agents`, `fn_execution_step_summary`), all mapped to a caller in **Implementation**.
- [ ] Both function kinds are present — `approach.md` §2. 6 scalar, 3 table-returning.
- [ ] `runner` can `CALL` all 5 procedures against RLS-protected tables without bypassing `tenant_isolation` — verifies the `SECURITY DEFINER` + `FORCE ROW LEVEL SECURITY` pairing actually closes the isolation gap it exists to close.
- [ ] Per-procedure and per-function documentation (purpose, parameters/return, a concrete usage example) — required submission deliverable (`PROCEDIMIENTOS.md`/`FUNCIONES.md`, `approach.md` §7). Not this spec's job to produce those files, but `deltas/process.docs.md` is the material they should be derived from.

## How to test

No SQL exists yet — this spec precedes implementation (unlike `deltas/triggers.spec.md`, which was written retroactively). Once implemented, the manual verification flow is:

1. `CALL core.sp_launch_execution('<pending-task-uuid>', 3);` → a new `core.executions` row with `attempt_number = 1`, `status = 'pending'`; the task flips to `progress` if it was `pending`.
2. `CALL trace.sp_record_execution_step('<execution-uuid>', '<agent-in-swarm-uuid>', '{}'::jsonb, ARRAY['search'], 500, 200, 0.001, 0.003);` → one row each in `trace.execution_steps` and `trace.token_costs`, with `estimated_cost` matching `fn_calculate_token_cost`'s formula.
3. Repeat step 2 with large `p_input_tokens`/`p_output_tokens` until the tenant's `fn_tenant_budget_threshold` is exceeded → the call raises and neither table gains a row for that attempt.
4. `CALL core.sp_complete_execution('<execution-uuid>', 'failed', 3);` on an execution with `attempt_number < 3` → the execution becomes `failed`, and a **new** `core.executions` row appears automatically (`attempt_number + 1`, `status = 'pending'`) via the internal `sp_launch_execution` call.
5. Repeat step 4 until `attempt_number = 3` fails → this time the task itself flips to `failed`, no new execution is created.
6. `CALL core.sp_complete_execution('<execution-with-zero-steps-uuid>', 'completed', 3);` → rejected: no rows from `fn_execution_step_summary`.
7. `CALL core.sp_provision_swarm_roster('<swarm-uuid>', ARRAY['<active-agent-uuid>', '<other-tenant-agent-uuid>']);` → only the same-tenant active agent ends up in `core.swarm_agents`; the other id is silently skipped, not rejected.
8. `CALL core.sp_archive_stale_swarms(now() - interval '90 days');` → every returned swarm from `core.fn_stale_swarms` becomes `archived`, and its `pending`/`progress` tasks become `failed`; `SELECT` mid-run (from another session) shows already-processed swarms committed even before the whole call finishes.

## Risks / edge cases

1. **`fn_next_attempt_number` duplicates `trg_executions_validate_attempt_number`'s own count query.** Both independently compute `count(*) + 1` for a task. Accepted (see **Scope**) as defense in depth — the procedure gives a clean, expected `attempt_number` up front; the trigger is still the actual enforcement point regardless of which code path inserts the row. A future change to attempt-numbering logic has to be made in both places, a known shotgun-surgery risk deliberately not fixed now.
2. **`fn_tenant_budget_threshold`'s three values are illustrative placeholders**, not derived from any real requirement in `approach.md` or a schema column — the model has no `budget_limit` field and `approach.md` disallows adding one. Revisiting these numbers doesn't require a migration, only editing the function body, but don't present them in the oral review as calibrated business figures.
3. **`sp_archive_stale_swarms` is not atomic across swarms.** Each swarm is archived and committed independently inside the `WHILE` loop; if the procedure is interrupted mid-run, already-processed swarms stay archived while the rest remain untouched. Accepted because each swarm's archival is independent — there's no cross-swarm invariant that a partial run would violate.
4. **`sp_complete_execution`'s auto-retry calls `sp_launch_execution` from within the same procedure call.** A caller who doesn't expect an automatic new attempt (e.g. a UI that just wants to record "this run failed") gets a side effect they didn't explicitly ask for. This is the deliberate, user-confirmed retry policy (see **Scope**), not an accidental coupling — documented here so it isn't "discovered" mid-implementation.
5. **`FORCE ROW LEVEL SECURITY` changes real query behavior for `sampler`**, not just for these new procedures — any *other* script or migration step that runs as `sampler` and touches these 9 tables (e.g. the seeders in `drizzle/customs/seeders/`, which run through `TenantScope` and therefore already set `app.current_tenant_id`) is now also subject to `tenant_isolation`. Verified the seeders already set tenant context before writing, so this shouldn't break `bun run drizz:seeding` — but it's the one place outside these 5 procedures where `FORCE` has a real, non-hypothetical effect worth re-checking after the migration lands.
6. **`sp_provision_swarm_roster` silently skips invalid agent ids** (wrong tenant, inactive, or already assigned) instead of raising per-id. A caller passing a partially-wrong batch gets a smaller roster than requested with no error — acceptable for a batch-assignment operation, but worth stating explicitly since every other procedure in this slice raises on invalid input.
7. **The rubric minimums are met with modest margin, not by a wide one.** 5/5 procedures, 9/8 functions. Removing or merging any procedure risks dropping below the graded minimum and losing one of the four required control-flow constructs (only one procedure supplies `FOR`, only one supplies `WHILE`, only one supplies `CASE`) — re-check the **Acceptance criteria** mapping before removing any of the 5.
