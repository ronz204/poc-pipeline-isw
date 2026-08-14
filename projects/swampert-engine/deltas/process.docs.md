# Business Procedures & Functions — Reference

What each procedure and function under `drizzle/customs/funcs/` does, in plain language, without reading the SQL line by line. Design rationale, deferred decisions, and invariants live in `process.spec.md` (same folder) — this file only explains behavior. All 14 objects described here exist (9 `.fn.sql` + 5 `.proc.sql`) and the whole flow has been run end to end; the one thing still missing is the DCL they assume (`FORCE ROW LEVEL SECURITY` and the `EXECUTE` grants), which has no applied home yet.

---

## Procedures

Five procedures automate the swarm/task/execution lifecycle. Four run as `sampler` (`SECURITY DEFINER`); `sp_archive_stale_swarms` runs as whoever calls it, because it commits per swarm and Postgres doesn't allow a `SECURITY DEFINER` routine to control transactions.

| Procedure | Schema | Touches | Control flow it contributes | Runs as |
|---|---|---|---|---|
| `sp_launch_execution` | `core` | `executions`, `tasks` | `IF/ELSE` | `sampler` |
| `sp_complete_execution` | `core` | `executions`, `tasks` (+ triggers a retry) | `CASE`, `IF/ELSE` | `sampler` |
| `sp_record_execution_step` | `trace` | `execution_steps`, `token_costs` | `IF` | `sampler` |
| `sp_provision_swarm_roster` | `core` | `swarm_agents` | `FOR` | `sampler` |
| `sp_archive_stale_swarms` | `core` | `swarms`, `tasks` | `WHILE` | the caller |

### `core.sp_launch_execution(p_task_id, p_max_attempts = 3)`

Starts a new execution attempt for a task. Rejects the call if the task doesn't exist, is soft-deleted, is already `completed`, if its swarm isn't `active`, or if the task has already used all `p_max_attempts` attempts. Works out the next `attempt_number` itself, inserts the new `core.executions` row as `pending`, and flips the task to `progress` if this is its first attempt. Both writes are one unit: if the task update fails, the execution insert is rolled back with it.

*Example:* `CALL core.sp_launch_execution('018f...-task', 3);`

### `core.sp_complete_execution(p_execution_id, p_status, p_max_attempts = 3)`

Closes out an execution. `p_status` must be `'completed'` or `'failed'` — anything else is rejected, as is an execution that is already terminal. Completing requires at least one recorded step (an execution with zero steps can't be marked done). On `'completed'`, the parent task becomes `completed`. On `'failed'`, the procedure checks the attempt count: if attempts remain, it automatically calls `sp_launch_execution` for the same task (a new attempt starts on its own — no separate retry call needed); once attempts are exhausted, the task itself becomes `failed` instead. The retry happens in the same transaction as the closure, so if the new attempt can't be launched — its swarm was archived in the meantime — the whole call fails and the execution stays open rather than being closed with the retry quietly skipped.

*Example:* `CALL core.sp_complete_execution('018f...-exec', 'failed', 3);`

### `trace.sp_record_execution_step(p_execution_id, p_agent_id, p_reasoning, p_tools_used, p_input_tokens, p_output_tokens, p_cost_per_1k_input, p_cost_per_1k_output)`

Logs one step of an execution together with its token cost. Rejects the call if the execution is already terminal or soft-deleted, or if the agent doesn't belong to the swarm the execution's task runs under. Computes the step's cost, and if the execution's running total (including this step) would exceed the tenant's plan-based budget threshold, rejects the whole call — no step and no cost row get written. Otherwise inserts both `trace.execution_steps` and `trace.token_costs` as one unit, the cost row pointing at the step just written. The step's position in the run is derived (highest `step_number` so far, plus one), not passed in — a caller-supplied number could leave gaps or duplicates in the trace.

*Example:* `CALL trace.sp_record_execution_step('018f...-exec', '018f...-agent', '{"summary":"searched docs"}'::jsonb, ARRAY['web_search'], 480, 210, 0.0010, 0.0030);`

### `core.sp_provision_swarm_roster(p_swarm_id, p_agent_ids)`

Assigns a batch of agents to a swarm in one call. Rejects the call outright if `p_agent_ids` is empty, or if the swarm doesn't exist, isn't active, or is soft-deleted. Then loops over the given agent ids: any id that isn't an active agent belonging to the same tenant is skipped (not rejected — see `process.spec.md` Risks); any id already on the roster is left alone; everything else gets inserted into `core.swarm_agents`. It ends with a notice reporting how many were added and how many skipped, which is the only signal a caller gets about the ones left out. A single-table operation, so it doesn't need the atomicity treatment the other procedures do.

*Example:* `CALL core.sp_provision_swarm_roster('018f...-swarm', ARRAY['018f...-agent1', '018f...-agent2']);`

### `core.sp_archive_stale_swarms(p_inactive_since)`

Batch job: finds every active swarm with no task created after the given timestamp and no execution still in progress, archives it, and fails any of its still-open tasks. A cutoff in the future is rejected — it would archive everything. Processes one swarm per loop iteration and commits after each one, so a failure partway through leaves already-processed swarms archived and unprocessed ones untouched. That per-iteration commit is only possible because this is a `PROCEDURE` and not a `FUNCTION`, and because — unlike the other four — it does *not* run as `sampler`: Postgres refuses transaction control inside a `SECURITY DEFINER` routine. Running as the caller means it needs the caller to hold `UPDATE` on `core.swarms` and `core.tasks`, which `runner` does today.

Two consequences of committing mid-run, both handled inside the procedure: the tenant setting is re-applied after each commit (a transaction-local one wouldn't survive), and the list of stale swarms is re-queried each iteration instead of being held open in a cursor (a commit closes cursors). It also stops with an error, rather than looping forever, if a swarm it just listed can't actually be updated.

*Example:* `CALL core.sp_archive_stale_swarms(now() - interval '90 days');`

---

## Functions

Nine functions, each called by at least one procedure above — six return a single scalar value, three return a table.

| Function | Schema | Returns | Called by |
|---|---|---|---|
| `fn_is_swarm_active` | `core` | `boolean` | `sp_launch_execution`, `sp_provision_swarm_roster` |
| `fn_next_attempt_number` | `core` | `integer` | `sp_launch_execution` |
| `fn_agent_belongs_to_swarm` | `core` | `boolean` | `sp_record_execution_step` |
| `fn_calculate_token_cost` | `trace` | `numeric` | `sp_record_execution_step` |
| `fn_tenant_budget_threshold` | `core` | `numeric` | `sp_record_execution_step` |
| `fn_execution_total_cost` | `trace` | `numeric` | `sp_record_execution_step` |
| `fn_stale_swarms` | `core` | table | `sp_archive_stale_swarms` |
| `fn_tenant_active_agents` | `core` | table | `sp_provision_swarm_roster` |
| `fn_execution_step_summary` | `trace` | table | `sp_complete_execution` |

### Scalar functions

- **`fn_is_swarm_active(p_swarm_id)`** — true if the swarm's `status = 'active'` and `deleted_at IS NULL`.
- **`fn_next_attempt_number(p_task_id)`** — how many executions already exist for the task, plus one. The same rule `trg_executions_validate_attempt_number` already enforces at the trigger level (see `process.spec.md` Risks for why the two aren't unified).
- **`fn_agent_belongs_to_swarm(p_agent_id, p_swarm_id)`** — true if that pair exists in `core.swarm_agents`.
- **`fn_calculate_token_cost(p_input_tokens, p_output_tokens, p_cost_per_1k_input, p_cost_per_1k_output)`** — pure arithmetic, no table access: `(input/1000 * cost_in) + (output/1000 * cost_out)`, rounded to the 4 decimals `token_costs.estimated_cost` stores. Rejects NULL and negative tokens or prices — a negative cost would lower an execution's total and quietly defeat the budget check.
- **`fn_tenant_budget_threshold(p_tenant_id)`** — looks up the tenant's `plan` and returns a fixed ceiling per tier (`basic`/`pro`/`enterprise`), raising if the tenant doesn't exist or is deleted rather than returning nothing and letting a budget check pass by default. The three numbers are illustrative placeholders, not a modeled business figure — see `process.spec.md` Risks.
- **`fn_execution_total_cost(p_execution_id)`** — sum of `trace.token_costs.estimated_cost` for the execution so far, ignoring soft-deleted cost rows, and `0` rather than nothing when there are none yet.

### Table-returning functions

- **`fn_stale_swarms(p_inactive_since)`** — active swarms with no task created after the given timestamp and no execution still `pending`/`running`. A swarm that never had a task counts as stale, with `last_task_at` empty. Returns `(swarm_id, tenant_id, last_task_at)`. Row-level security scopes it to the current tenant, so it lists that tenant's stale swarms, not the whole database's.
- **`fn_tenant_active_agents(p_tenant_id)`** — every active, non-soft-deleted agent belonging to the tenant, ordered by name. Returns `(agent_id, name, role)`.
- **`fn_execution_step_summary(p_execution_id)`** — every recorded step for the execution, in order, minus the reasoning payload and minus soft-deleted steps. Returns `(step_number, agent_id, tools_used, occurred_at)`; an empty result is what `sp_complete_execution` checks to block completing a step-less execution.

---

## Multi-tenant isolation and `SECURITY DEFINER`

Four of the five procedures run as `sampler` (the schema owner), not as `runner`. That is why they depend on `ALTER TABLE ... FORCE ROW LEVEL SECURITY` on the 9 tenant-scoped tables: without `FORCE`, `sampler`-as-owner skips the `tenant_isolation` policy while running a procedure body, silently breaking the isolation these procedures are supposed to preserve. `sp_archive_stale_swarms` is the exception — it runs as the caller so it can commit per swarm, and is therefore subject to RLS the ordinary way.

That DCL, together with `EXECUTE` for `runner`, has not been applied yet: it has no migration and no hand-applied file (see `process.spec.md` § Implementation). Nothing revokes anything — `runner` keeps every direct table privilege it has today, which is also what `sp_archive_stale_swarms` currently relies on to do its updates.

## Calling them

Every procedure reads and writes tenant-scoped tables, so `app.current_tenant_id` must be set for the calling session or transaction — otherwise the rows simply aren't there, and a call fails with "does not exist" rather than with a permissions error:

```sql
SELECT set_config('app.current_tenant_id', '<tenant-uuid>', false);
CALL core.sp_launch_execution('<task-uuid>', 3);
```

`sp_archive_stale_swarms` is the one with a stricter contract: because it commits inside its loop, it must be called outside a transaction the caller opened itself. The other four never end the caller's transaction, so they are safe to call from inside `TenantScope.run()`, where the tenant is set with `SET LOCAL`.
