# Business Procedures & Functions — Spec

## Objective

Automate the swarm/task/execution business lifecycle as 5 stored procedures — launching an execution attempt, closing one (with automatic retry), recording an execution step and its cost, provisioning a swarm's agent roster, and archiving stale swarms — each backed by reusable functions, so that a single `CALL` replaces what today would require several hand-run, unvalidated statements. Every procedure validates its inputs and fails with a declared exception instead of letting an invalid state persist; every procedure touching more than one table makes its multi-table write atomic, through an inner `BEGIN`/`EXCEPTION` subtransaction block (4 of them) or a per-iteration `COMMIT` (the batch archiver — see **Technical context** for why the two differ). This satisfies `approach.md` §1 (Procedimientos, 18 pts) and §2 (Funciones, 15 pts).

## Scope

**In scope:**

- 5 procedures: `core.sp_launch_execution`, `core.sp_complete_execution`, `trace.sp_record_execution_step`, `core.sp_provision_swarm_roster`, `core.sp_archive_stale_swarms` — implemented as `.proc.sql` files under `drizzle/customs/funcs/` (see **Technical context** for why this directory, not a new `procs/`).
- 9 functions (6 scalar, 3 table-returning), as `.fn.sql` files in the same directory — see **Implementation**.
- The DCL these procedures require: `FORCE ROW LEVEL SECURITY` on the 9 tenant-scoped tables, and `EXECUTE` on the 5 procedures for `runner`. **Not applied yet** — see **Implementation** § Migration.

**Deliberately out of scope, confirmed with the user:**

- **Physical purge.** No procedure issues a `DELETE`. Every destructive-sounding process (swarm going stale, an execution exhausting its retries) resolves as a status transition (`archived`, `failed`) or the existing `deleted_at` soft-delete column — never a row physically removed. A hard-delete retention procedure was considered and explicitly rejected as too risky to demo live in the oral review.
- **Refactoring `trg_executions_validate_attempt_number` to reuse `core.fn_next_attempt_number`.** The trigger keeps its own inline `count(*) + 1` query. The new function duplicates that logic for `sp_launch_execution`'s own use. This is accepted duplication (see **Risks**), not an oversight — touching an already-shipped, spec'd trigger (`deltas/triggers.spec.md`) is a different slice.
- **Revoking `runner`'s direct table privileges.** `database.md` documents the eventual plan (`SECURITY DEFINER` procedures replace direct writes, `runner` ends up with `SELECT` + `EXECUTE` only) but the user explicitly confirmed this slice is additive only: `runner` keeps every privilege it has today, and only gains `EXECUTE` on the 5 new procedures. Verified today that `projects/swampert-engine/source/` contains no `.insert()`/`.update()`/`.delete()` call at all, so nothing currently depends on direct writes — but the revocation itself is left for a future slice, not bundled here. When that slice happens, note that `sp_archive_stale_swarms` does not fit the "`SECURITY DEFINER` replaces direct writes" plan — it runs as its caller by necessity (see **Technical context**) and needs `UPDATE` on `core.swarms`/`core.tasks` kept or re-granted.
- **Automated tests.** Same accepted state as `deltas/triggers.spec.md` — no `pgTAP`/`bun test` coverage exists in the repo for any procedure or function. The full flow *has* been verified end to end (see **How to test**), but against a throwaway container and with a script that wasn't committed, so nothing re-runs it automatically.
- **Summary tables and the dashboard.** Separate rubric components (`approach.md` §5–6), not this slice's job, even though `sp_complete_execution` and `sp_record_execution_step` are exactly the writes those summary tables will eventually aggregate.

## Technical context

- Domain model verified against `drizzle/elements/{auth,core,trace,roles}.element.ts`. Relevant chains: `core.tasks.swarm_id → core.swarms.id`, `core.executions.task_id → core.tasks.id`, `trace.execution_steps.{execution_id, agent_id}`, `trace.token_costs.{execution_id, step_id}`. `core.swarm_agents` is a pure junction table (composite PK, no `tenant_id`, no RLS) already protected by `trg_swarm_agents_validate_tenant` (`deltas/triggers.spec.md`).
- Enums used by the new procedures/functions, confirmed against `core.element.ts`/`auth.element.ts`: `core.swarm_status` (`active`/`paused`/`archived`), `core.task_status` (`pending`/`progress`/`completed`/`failed`), `core.execution_status` (`pending`/`running`/`completed`/`failed`), `auth.tenant_plan` (`basic`/`pro`/`enterprise`).
- **Existing triggers this slice must not fight.** `trg_executions_validate_transition` already rejects reopening a terminal execution and any `finished_at < started_at`; `trg_executions_validate_attempt_number` already rejects a non-consecutive `attempt_number` on `INSERT`; `trg_tasks_validate_swarm_active` already rejects creating a task on an archived/soft-deleted swarm. The new procedures validate the same conditions *before* attempting the write (so the caller gets a clear, procedure-level exception instead of relying on the trigger to reject it), but the triggers remain the last line of defense regardless of which code path writes the row.
- **File placement.** `engine.md` establishes `.trg.sql` for triggers and (implicitly, via the 2 existing files) `.fn.sql` for functions, both flat inside `drizzle/customs/<kind>/`. The user chose to keep procedures in the same directory as functions (`drizzle/customs/funcs/`) rather than a new `drizzle/customs/procs/`, differentiated by extension (`.proc.sql` vs `.fn.sql`) and SQL name prefix (`sp_` vs `fn_`) — one less top-level directory, and procedures/functions are already closely related (every procedure calls at least one function).
- **`SECURITY DEFINER` and RLS.** `database.md` § Postgres roles already names this exact milestone as the trigger for two follow-ups: procedures owned by `sampler` need `FORCE ROW LEVEL SECURITY` on every tenant-scoped table (today only `ENABLE`), because otherwise `sampler`-as-owner would bypass `tenant_isolation` while executing the procedure body; and `runner` needs `EXECUTE` on the procedures to call them at all. `FORCE` is not optional once these procedures exist, it's what keeps them from silently defeating multi-tenant isolation the moment they run. Neither statement is applied yet (see **Implementation** § Migration).
- **Postgres forbids transaction control inside `SECURITY DEFINER` routines.** A `COMMIT` (or `ROLLBACK`) in a `SECURITY DEFINER` procedure fails at runtime with `invalid transaction termination` — verified directly against Postgres 16 with a two-line procedure, not inferred. This is the single constraint that shaped the whole transaction design of this slice, and it forces a choice per procedure: run as the owner, or control transactions — never both.
  - The 4 procedures that need owner privileges keep `SECURITY DEFINER` and drop the `COMMIT`. Their multi-table writes go in an inner `BEGIN ... EXCEPTION WHEN OTHERS THEN RAISE ... END` block, which *is* a real subtransaction: a failure in the second write rolls the first one back before the error reaches the caller. The `CALL` itself is the commit boundary, so the procedure is still all-or-nothing — which is what `approach.md` §1's transaction requirement is actually about.
  - `core.sp_archive_stale_swarms` needs the opposite trade: committing per swarm is its entire reason for existing as a batch job, so it is the one procedure declared **without** `SECURITY DEFINER`. It runs as the caller (`runner`), which already holds direct `UPDATE` on `core.swarms`/`core.tasks` under the concession documented in `database.md`. If `runner`'s direct table privileges are ever revoked, this procedure — and only this one — needs explicit grants on those two tables.
  - The `EXCEPTION WHEN OTHERS THEN ROLLBACK; RAISE;` pattern this spec originally called for doesn't work regardless of the above: per Postgres' documented rule, transaction control is rejected while a subtransaction is active — which is exactly what being inside an exception handler means. The handler re-raises with the procedure's name and parameters attached (`USING ERRCODE = SQLSTATE` preserves the original code) instead, and the subtransaction rollback happens on its own.
- **A `COMMIT` discards a transaction-local tenant setting.** `TenantScope.run()` sets `app.current_tenant_id` with `set_config(..., true)`, which dies with the transaction. That makes the per-swarm `COMMIT` in `sp_archive_stale_swarms` a real hazard under RLS — the next iteration would see no rows. The procedure captures the setting before the loop and re-applies it at session level after every `COMMIT`; the other four never end a transaction, so they are safe to call from inside `TenantScope.run()`.
- `engine.md`'s "classes over standalone functions" convention is TypeScript-specific and doesn't apply here — `.proc.sql`/`.fn.sql` are raw SQL artifacts owned by Postgres, the same reasoning that already keeps `.trg.sql` files as plain SQL rather than wrapped in application code.
- `approach.md` is in Spanish; this spec (like `deltas/triggers.spec.md`) restates its requirements in English to match this project's established `.claude/docs/`/`deltas/*.md` language.

## Implementation

### Procedures

**1. `core.sp_launch_execution(p_task_id uuid, p_max_attempts integer DEFAULT 3)`** — `launch_execution.proc.sql`, `SECURITY DEFINER`
Starts a new execution attempt for a task.
- Validates: `p_task_id` not null and `p_max_attempts >= 1`; task exists and isn't soft-deleted; task isn't already `completed`; `core.fn_is_swarm_active(swarm_id)` is true for the task's swarm.
- `v_attempt := core.fn_next_attempt_number(p_task_id)`, then rejects `v_attempt > p_max_attempts`. This is what gives `p_max_attempts` a job of its own here instead of being a parameter only passed through: a task that burned its 3 attempts can't be relaunched by hand.
- `INSERT INTO core.executions (..., attempt_number, status, started_at) VALUES (..., v_attempt, 'pending', now())`.
- `IF` the task's current status is `pending` `THEN` update it to `progress` — otherwise leave it (already `progress` from a prior attempt).
- Touches `core.executions` + `core.tasks` → both writes inside one inner `BEGIN`/`EXCEPTION` block.

**2. `core.sp_complete_execution(p_execution_id uuid, p_status core.execution_status, p_max_attempts integer DEFAULT 3)`** — `complete_execution.proc.sql`, `SECURITY DEFINER`
Closes an execution, with automatic retry on failure.
- Validates: `p_status` is exactly `'completed'` or `'failed'`; `p_max_attempts >= 1`; execution exists, isn't soft-deleted, and its current status isn't already `completed`/`failed`; if `p_status = 'completed'`, at least one row comes back from `trace.fn_execution_step_summary(p_execution_id)` — an execution can't be marked done with zero recorded work.
- `UPDATE core.executions SET status = p_status, finished_at = now() WHERE id = p_execution_id`.
- `CASE p_status`:
  - `WHEN 'completed'` → `UPDATE core.tasks SET status = 'completed' WHERE id = v_task_id`.
  - `WHEN 'failed'` → `IF v_attempt_number < p_max_attempts THEN CALL core.sp_launch_execution(v_task_id, p_max_attempts); ELSE UPDATE core.tasks SET status = 'failed' ...; END IF`.
  - `ELSE RAISE EXCEPTION` — unreachable given the up-front validation, kept so a future enum value surfaces as a clear message instead of `CASE_NOT_FOUND`.
- Touches `core.executions` + `core.tasks` (plus, on retry, whatever `sp_launch_execution` writes) → all of it inside one inner `BEGIN`/`EXCEPTION` block. The retry runs in this same transaction, so a retry that can't launch fails the whole call and leaves the execution open, instead of closing it with the retry silently skipped (see **Risks**).

**3. `trace.sp_record_execution_step(p_execution_id uuid, p_agent_id uuid, p_reasoning jsonb, p_tools_used text[], p_input_tokens integer, p_output_tokens integer, p_cost_per_1k_input numeric, p_cost_per_1k_output numeric)`** — `record_execution_step.proc.sql`, `SECURITY DEFINER`
Records one execution step together with its token cost.
- Resolves `v_swarm_id`/`v_tenant_id` with a direct `execution → task → swarm` join (no dedicated function — a one-line join doesn't earn its own reusable unit).
- Validates: execution exists, isn't soft-deleted, and its status isn't terminal; `core.fn_agent_belongs_to_swarm(p_agent_id, v_swarm_id)` is true. `p_reasoning`/`p_tools_used` accept `NULL` and are stored as `'{}'`/empty array.
- `v_cost := trace.fn_calculate_token_cost(...)` — which is also where non-negative tokens/prices are enforced.
- `IF trace.fn_execution_total_cost(p_execution_id) + v_cost > core.fn_tenant_budget_threshold(v_tenant_id) THEN RAISE EXCEPTION` — blocks before either insert happens.
- `step_number` is derived as `max(step_number) + 1` within the execution rather than received: a caller-supplied value could create gaps or duplicates in a run's trace, and there is no trigger on `trace.execution_steps` to catch that (unlike `attempt_number` on executions).
- `INSERT INTO trace.execution_steps (...)`, then `INSERT INTO trace.token_costs (..., step_id, estimated_cost)` pointing at the step just written → both inside one inner `BEGIN`/`EXCEPTION` block.

**4. `core.sp_provision_swarm_roster(p_swarm_id uuid, p_agent_ids uuid[])`** — `provision_swarm_roster.proc.sql`, `SECURITY DEFINER`
Assigns a batch of agents to a swarm.
- Validates: `p_agent_ids` has at least one element; swarm exists, isn't soft-deleted, and is active.
- `FOR v_agent_id IN SELECT unnest(p_agent_ids) LOOP`: skip any id not present in `core.fn_tenant_active_agents(v_tenant_id)` (wrong tenant or inactive); skip any pair already in `core.swarm_agents`; insert the rest. Ends with a `RAISE NOTICE` reporting added/skipped counts — the only signal a caller gets about skipped ids.
- Single table (`core.swarm_agents`) touched across all iterations — no explicit transaction of its own; `approach.md`'s transaction requirement is conditional on ">1 table" and genuinely doesn't apply here.

**5. `core.sp_archive_stale_swarms(p_inactive_since timestamptz)`** — `archive_stale_swarms.proc.sql`, **not** `SECURITY DEFINER` (see **Technical context**)
Batch job: archives swarms with no recent activity.
- Validates: `p_inactive_since` not null and not in the future — a future cutoff would archive every active swarm.
- `WHILE` there is a stale swarm: `UPDATE core.swarms SET status = 'archived'`; `UPDATE core.tasks SET status = 'failed' WHERE swarm_id = ... AND status IN ('pending', 'progress') AND deleted_at IS NULL`; `COMMIT`; re-apply the tenant setting; fetch the next one.
- **Re-queries `core.fn_stale_swarms(p_inactive_since) LIMIT 1` each iteration instead of holding a cursor open** — a cursor is closed by the `COMMIT`, so a cursor-based loop would break on the second fetch. Re-querying is safe because an archived swarm no longer matches (`fn_stale_swarms` only looks at `active` ones).
- **`GET DIAGNOSTICS ... ROW_COUNT` guards the loop**: if the swarm `UPDATE` matches nothing (the realistic cause being a missing `app.current_tenant_id` under RLS), the procedure raises instead of re-fetching the same swarm forever.
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

Each function lives in its own file named after the object without the prefix (`is_swarm_active.fn.sql` → `core.fn_is_swarm_active`), matching how `drizzle/customs/triggers/` already names its files. All 9 are `SECURITY INVOKER` (the Postgres default, same as the existing trigger functions): the 4 `SECURITY DEFINER` procedures already run as `sampler`, so functions called from them inherit that context without needing their own privilege escalation.

Behaviors decided while implementing, beyond "returns what the table says":

- **Soft-deleted rows are excluded** by `fn_execution_total_cost` (a retracted cost stops consuming budget), `fn_execution_step_summary` (a retracted step doesn't keep an empty execution completable) and `fn_tenant_active_agents`. `fn_next_attempt_number` deliberately does **not** filter them — it has to count exactly what `trg_executions_validate_attempt_number` counts, or the procedure starts failing its own trigger.
- **`fn_calculate_token_cost`** rejects `NULL` and negative tokens/prices (a negative cost would quietly lower an execution's total and defeat the budget check) and rounds to 4 decimals, the scale `trace.token_costs.estimated_cost` stores — so the value checked against the budget is byte-for-byte the value written.
- **`fn_stale_swarms`** treats a swarm with zero tasks as stale, returning `last_task_at` as `NULL`. Under RLS it only ever sees the current tenant's swarms, so it is a per-tenant list, not a global sweep.
- **`fn_tenant_budget_threshold`** raises when the tenant doesn't exist or is soft-deleted, rather than returning `NULL` and letting the budget comparison silently pass.

`core.fn_tenant_budget_threshold` is the one function whose body is a `CASE` on `auth.tenants.plan`:

```sql
CASE v_plan
  WHEN 'basic'      THEN 50.00
  WHEN 'pro'        THEN 250.00
  WHEN 'enterprise' THEN 1000.00
END
```

These three numbers are illustrative placeholders, not a requirement derived from `approach.md` or any real pricing decision — `approach.md` requires reusing the data model without structural changes, so there is no `budget_limit` column to read instead. See **Risks**.

### Migration — still pending

**No migration was created for this slice, and the DCL below is not applied yet.** This is a change of plan from what this section originally specified, and it follows what the repo actually does now: commits `69db2bc`/`caafc7c` deleted the mirrored `modeling_audit`/`granting_audit` migrations and re-created the triggers and functions as hand-applied files under `drizzle/customs/`. `drizzle/migrations/` today holds only the 6 original schema/DCL migrations, so adding a migration for these 14 objects would reintroduce exactly the duplication that was deliberately removed.

What that leaves open: the objects themselves are applied by running the `.fn.sql`/`.proc.sql` files (functions before procedures before triggers — the trigger files fail if `fn_log_audit_change` doesn't exist yet), but the DCL has no home yet. Until it is applied, the procedures work only because `runner` still has direct table privileges, and `sampler` — as owner of the `SECURITY DEFINER` bodies — bypasses `tenant_isolation` on tables that are only `ENABLE`, not `FORCE`. Deciding where this DCL lives (a `granting_procedures` migration, following the surviving DCL migrations, or a hand-applied file next to the customs SQL) is the immediate next step for this slice:

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
  No `REVOKE` statement — `runner` keeps every direct table privilege it has today (see **Scope**). Two things to get right when this is finally applied: Postgres grants `EXECUTE` on new routines to `PUBLIC` by default, so the `GRANT` above documents intent more than it changes access (revoking from `PUBLIC` first is what would make it meaningful); and `sp_archive_stale_swarms`, being the one procedure that runs as its caller, needs `runner` to keep `UPDATE` on `core.swarms`/`core.tasks` — it stops working the day those privileges are revoked, unlike the other four.

## Acceptance criteria

- [x] At least 5 procedures exist, each automating a real multi-step process (not a trivial single-table write) — `approach.md` §1. Current count: 5 (`sp_launch_execution`, `sp_complete_execution`, `sp_record_execution_step`, `sp_provision_swarm_roster`, `sp_archive_stale_swarms`).
- [x] Across the 5 procedures, `IF/ELSE`, `CASE`, `FOR`, and `WHILE` each appear at least once — `approach.md` §1. Mapping: `IF/ELSE` in `sp_launch_execution`/`sp_complete_execution`/`sp_record_execution_step`; `CASE` in `sp_complete_execution`; `FOR` in `sp_provision_swarm_roster`; `WHILE` in `sp_archive_stale_swarms`.
- [x] Every procedure receives real parameters (ids, quantities, dates) and validates them, raising a declared exception on invalid input — no hardcoded values — `approach.md` §1.
- [x] Every procedure that writes to more than one table makes those writes atomic — `approach.md` §1. Met as an inner `BEGIN`/`EXCEPTION` subtransaction block in `sp_launch_execution`/`sp_complete_execution`/`sp_record_execution_step`, and as a per-swarm `COMMIT` in `sp_archive_stale_swarms`. `sp_provision_swarm_roster` is single-table and documented as not applicable. Note this is the requirement met by its intent, not by literal `BEGIN`/`COMMIT`/`ROLLBACK` statements in all four — Postgres forbids those in `SECURITY DEFINER` routines (see **Technical context**), which is the one point in this slice worth being ready to defend out loud in the oral review.
- [x] At least 8 functions exist, each used by at least one of the 5 procedures — `approach.md` §2. Current count: 9 (`fn_is_swarm_active`, `fn_next_attempt_number`, `fn_agent_belongs_to_swarm`, `fn_calculate_token_cost`, `fn_tenant_budget_threshold`, `fn_execution_total_cost`, `fn_stale_swarms`, `fn_tenant_active_agents`, `fn_execution_step_summary`), all mapped to a caller in **Implementation**.
- [x] Both function kinds are present — `approach.md` §2. 6 scalar, 3 table-returning.
- [x] `runner` can `CALL` all 5 procedures against RLS-protected tables without bypassing `tenant_isolation` — verified with `FORCE ROW LEVEL SECURITY` applied on all 9 tables and `runner` connecting directly (see **How to test**): every procedure worked, and switching `app.current_tenant_id` to a second tenant made the first tenant's swarms and executions invisible.
- [ ] `FORCE ROW LEVEL SECURITY` and the `EXECUTE` grants are applied to the real database — not done; the DCL has no migration or applied home yet (see **Implementation** § Migration). Until then, the isolation guarantee above holds only where that DCL has been run by hand.
- [ ] Per-procedure and per-function documentation (purpose, parameters/return, a concrete usage example) — required submission deliverable (`PROCEDIMIENTOS.md`/`FUNCIONES.md`, `approach.md` §7). Not this spec's job to produce those files, but `deltas/process.docs.md` is the material they should be derived from.

## How to test

This flow was run end to end and every expectation below is what actually happened, not what should happen. Setup used: a throwaway `postgres:16-alpine` container, `bootstrap.sql` (roles) → the 6 existing migrations → the `.fn.sql` files → the `.proc.sql` files → the `.trg.sql` files (in that order — the trigger files fail if `trace.fn_log_audit_change` doesn't exist yet), then the DCL from **Implementation**, all applied as `sampler`. Seed: two tenants, one swarm with one active agent and one `pending` task, one inactive agent, one agent belonging to the other tenant, one swarm with no tasks and one abandoned swarm with a 100-day-old open task. Every `CALL` below was then issued **as `runner`**, with `SELECT set_config('app.current_tenant_id', '<uuid>', false);` first.

1. `CALL core.sp_provision_swarm_roster('<swarm>', ARRAY['<active-agent>', '<other-tenant-agent>', '<inactive-agent>']::uuid[]);` → `NOTICE: 1 agent(s) added, 2 skipped`, and only the same-tenant active agent is in `core.swarm_agents`. Repeating the call adds nothing (`0 added, 1 skipped`).
2. `CALL core.sp_launch_execution('<pending-task>', 3);` → a `core.executions` row with `attempt_number = 1`, `status = 'pending'`; the task moves to `progress`.
3. `CALL trace.sp_record_execution_step('<execution>', '<agent-on-roster>', '{"summary":"searched the docs"}'::jsonb, ARRAY['web_search'], 480, 210, 0.0010, 0.0030);` → one row each in `trace.execution_steps` (`step_number = 1`) and `trace.token_costs` (`estimated_cost = 0.0011`, matching `fn_calculate_token_cost`).
4. Same call with `100000000` input tokens at `10.0` per 1k → rejected: *"would reach 1000000.0011, over the tenant budget of 250.00"*, and both tables still hold exactly the one row from step 3.
5. Same call with the inactive agent (not on the roster) → rejected: *"is not on the roster of swarm"*.
6. `CALL core.sp_complete_execution('<execution>', 'failed', 3);` → attempt 1 becomes `failed` with `finished_at` set, and attempt 2 appears automatically as `pending`; the task stays `progress`.
7. `CALL core.sp_complete_execution('<attempt-2>', 'completed', 3);` → rejected: *"no steps were recorded"*. `CALL ... 'running' ...` → rejected: *"p_status must be 'completed' or 'failed'"*.
8. Failing attempts 2 and 3 → three `failed` executions, the task itself becomes `failed`, and no attempt 4 is created. `CALL core.sp_launch_execution('<same-task>', 3);` afterwards → rejected: *"already used its 3 allowed attempts"*.
9. `CALL core.sp_archive_stale_swarms(now() - interval '1 day');` → both quiet swarms are archived one at a time (`NOTICE` per swarm), the abandoned swarm's open task becomes `failed` (`Done: 2 swarm(s) archived, 1 task(s) failed`), and the swarm with a live execution is left `active`. `CALL core.sp_archive_stale_swarms(now() + interval '1 day');` → rejected as a future cutoff.
10. `SELECT set_config('app.current_tenant_id', '<other-tenant>', false);` then `SELECT count(*) FROM core.swarms;` → `0`, same for `core.executions`, and `CALL core.sp_launch_execution('<first-tenant-task>', 3);` → *"Task ... does not exist"*. Tenant isolation holds through `SECURITY DEFINER` bodies.
11. `SELECT entity_type, action, count(*) FROM trace.audit_log GROUP BY 1, 2;` → the procedures' writes are audited like any other (`executions created/updated`, `tasks updated`, `swarms updated`), confirming the trigger layer from `deltas/triggers.spec.md` sees procedure traffic with no extra wiring.

## Risks / edge cases

1. **`fn_next_attempt_number` duplicates `trg_executions_validate_attempt_number`'s own count query.** Both independently compute `count(*) + 1` for a task. Accepted (see **Scope**) as defense in depth — the procedure gives a clean, expected `attempt_number` up front; the trigger is still the actual enforcement point regardless of which code path inserts the row. A future change to attempt-numbering logic has to be made in both places, a known shotgun-surgery risk deliberately not fixed now.
2. **`fn_tenant_budget_threshold`'s three values are illustrative placeholders**, not derived from any real requirement in `approach.md` or a schema column — the model has no `budget_limit` field and `approach.md` disallows adding one. Revisiting these numbers doesn't require a migration, only editing the function body, but don't present them in the oral review as calibrated business figures.
3. **`sp_archive_stale_swarms` is not atomic across swarms.** Each swarm is archived and committed independently inside the `WHILE` loop; if the procedure is interrupted mid-run, already-processed swarms stay archived while the rest remain untouched. Accepted because each swarm's archival is independent — there's no cross-swarm invariant that a partial run would violate.
4. **`sp_complete_execution`'s auto-retry calls `sp_launch_execution` from within the same procedure call.** A caller who doesn't expect an automatic new attempt (e.g. a UI that just wants to record "this run failed") gets a side effect they didn't explicitly ask for. This is the deliberate, user-confirmed retry policy (see **Scope**), not an accidental coupling — documented here so it isn't "discovered" mid-implementation.
5. **`FORCE ROW LEVEL SECURITY` changes real query behavior for `sampler`**, not just for these new procedures — any *other* script or migration step that runs as `sampler` and touches these 9 tables (e.g. the seeders in `drizzle/customs/seeders/`, which run through `TenantScope` and therefore already set `app.current_tenant_id`) is now also subject to `tenant_isolation`. Verified the seeders already set tenant context before writing, so this shouldn't break `bun run drizz:seeding` — but it's the one place outside these 5 procedures where `FORCE` has a real, non-hypothetical effect worth re-checking once the DCL is finally applied.
6. **`sp_provision_swarm_roster` silently skips invalid agent ids** (wrong tenant, inactive, or already assigned) instead of raising per-id. A caller passing a partially-wrong batch gets a smaller roster than requested with no error — acceptable for a batch-assignment operation, but worth stating explicitly since every other procedure in this slice raises on invalid input.
7. **Four of the five procedures contain no literal `COMMIT`/`ROLLBACK` statement**, because Postgres refuses transaction control inside `SECURITY DEFINER` routines (**Technical context**). A reading of `approach.md` §1 that greps for the keywords rather than for atomicity would score this as missing. The atomicity itself is real and demonstrable (step 4 of **How to test** shows a rejected step leaving neither table written), and `sp_archive_stale_swarms` does contain real `COMMIT`s — but be ready to explain the constraint rather than being surprised by the question.
8. **The security model is deliberately mixed**, and that asymmetry is easy to "fix" by mistake. Adding `SECURITY DEFINER` to `sp_archive_stale_swarms` for consistency breaks it at runtime the first time it commits; removing it from the other four silently changes who their writes run as. Neither is a style choice.
9. **`sp_archive_stale_swarms` re-applies `app.current_tenant_id` at session level** (`set_config(..., false)`) after each `COMMIT`, because a transaction-local setting doesn't survive one. On a pooled connection that value outlives the call and is inherited by whatever runs next on that connection. Acceptable for a batch job run on its own connection; a real hazard if it's ever called from the pooled application path.
10. **A retry that can't launch fails the whole closure.** Because `sp_complete_execution`'s retry shares its transaction, if `sp_launch_execution` rejects (its swarm was archived meanwhile), the execution isn't marked `failed` at all — the caller must fix the swarm or close the execution with attempts already exhausted. The alternative (close first, retry after a `COMMIT`) is unavailable under `SECURITY DEFINER`; surfacing the failure was chosen over silently skipping the retry.
11. **The rubric minimums are met with modest margin, not by a wide one.** 5/5 procedures, 9/8 functions. Removing or merging any procedure risks dropping below the graded minimum and losing one of the four required control-flow constructs (only one procedure supplies `FOR`, only one supplies `WHILE`, only one supplies `CASE`) — re-check the **Acceptance criteria** mapping before removing any of the 5.
