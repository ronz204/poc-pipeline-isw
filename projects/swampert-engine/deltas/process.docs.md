# Business Procedures & Functions — Reference

What each planned procedure and function under `drizzle/customs/funcs/` does, in plain language, without reading the SQL line by line. Design rationale, deferred decisions, and invariants live in `process.spec.md` (same folder) — this file only explains behavior. **Nothing described here is implemented yet** — this is the pre-implementation reference for the slice specified in `process.spec.md`, written before a single `.proc.sql`/`.fn.sql` file exists.

---

## Procedures

Five procedures automate the swarm/task/execution lifecycle. Each is `SECURITY DEFINER` (owned by `sampler`) and callable by `runner` via `EXECUTE`.

| Procedure | Schema | Touches | Control flow it contributes |
|---|---|---|---|
| `sp_launch_execution` | `core` | `executions`, `tasks` | `IF/ELSE` |
| `sp_complete_execution` | `core` | `executions`, `tasks` (+ triggers a retry) | `CASE`, `IF/ELSE` |
| `sp_record_execution_step` | `trace` | `execution_steps`, `token_costs` | `IF` |
| `sp_provision_swarm_roster` | `core` | `swarm_agents` | `FOR` |
| `sp_archive_stale_swarms` | `core` | `swarms`, `tasks` | `WHILE` |

### `core.sp_launch_execution(p_task_id, p_max_attempts = 3)`

Starts a new execution attempt for a task. Rejects the call if the task doesn't exist, is soft-deleted, is already `completed`, or its swarm isn't `active`. Works out the next `attempt_number` itself, inserts the new `core.executions` row as `pending`, and flips the task to `progress` if this is its first attempt. Runs in an explicit transaction since it writes two tables.

*Example:* `CALL core.sp_launch_execution('018f...-task', 3);`

### `core.sp_complete_execution(p_execution_id, p_status, p_max_attempts = 3)`

Closes out an execution. `p_status` must be `'completed'` or `'failed'` — anything else is rejected. Completing requires at least one recorded step (an execution with zero steps can't be marked done). On `'completed'`, the parent task becomes `completed`. On `'failed'`, the procedure checks the attempt count: if attempts remain, it automatically calls `sp_launch_execution` for the same task (a new attempt starts on its own — no separate retry call needed); once attempts are exhausted, the task itself becomes `failed` instead.

*Example:* `CALL core.sp_complete_execution('018f...-exec', 'failed', 3);`

### `trace.sp_record_execution_step(p_execution_id, p_agent_id, p_reasoning, p_tools_used, p_input_tokens, p_output_tokens, p_cost_per_1k_input, p_cost_per_1k_output)`

Logs one step of an execution together with its token cost. Rejects the call if the execution is already terminal, or if the agent doesn't belong to the swarm the execution's task runs under. Computes the step's cost, and if the execution's running total (including this step) would exceed the tenant's plan-based budget threshold, rejects the whole call — no step and no cost row get written. Otherwise inserts both `trace.execution_steps` and `trace.token_costs` in one transaction.

*Example:* `CALL trace.sp_record_execution_step('018f...-exec', '018f...-agent', '{"summary":"searched docs"}'::jsonb, ARRAY['web_search'], 480, 210, 0.0010, 0.0030);`

### `core.sp_provision_swarm_roster(p_swarm_id, p_agent_ids)`

Assigns a batch of agents to a swarm in one call. Rejects the call outright if the swarm doesn't exist, isn't active, or is soft-deleted. Then loops over the given agent ids: any id that isn't an active agent belonging to the same tenant is silently skipped (not rejected — see `process.spec.md` Risks); any id already on the roster is left alone; everything else gets inserted into `core.swarm_agents`. A single-table operation, so it doesn't need the explicit-transaction treatment the other procedures do.

*Example:* `CALL core.sp_provision_swarm_roster('018f...-swarm', ARRAY['018f...-agent1', '018f...-agent2']);`

### `core.sp_archive_stale_swarms(p_inactive_since)`

Batch job: finds every active swarm with no task created after the given timestamp and no execution still in progress, archives it, and fails any of its still-open tasks. Processes one swarm per loop iteration and commits after each one — a real batch-job pattern, only possible because this is a `PROCEDURE` and not a `FUNCTION` (functions can't control transactions in Postgres). A failure partway through leaves already-processed swarms archived; unprocessed ones are untouched.

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
- **`fn_calculate_token_cost(p_input_tokens, p_output_tokens, p_cost_per_1k_input, p_cost_per_1k_output)`** — pure arithmetic, no table access: `(input/1000 * cost_in) + (output/1000 * cost_out)`.
- **`fn_tenant_budget_threshold(p_tenant_id)`** — looks up the tenant's `plan` and returns a fixed ceiling per tier (`basic`/`pro`/`enterprise`). The three numbers are illustrative placeholders, not a modeled business figure — see `process.spec.md` Risks.
- **`fn_execution_total_cost(p_execution_id)`** — sum of `trace.token_costs.estimated_cost` for the execution so far.

### Table-returning functions

- **`fn_stale_swarms(p_inactive_since)`** — active swarms with no task created after the given timestamp and no execution still `pending`/`running`. Returns `(swarm_id, tenant_id, last_task_at)`.
- **`fn_tenant_active_agents(p_tenant_id)`** — every active, non-soft-deleted agent belonging to the tenant. Returns `(agent_id, name, role)`.
- **`fn_execution_step_summary(p_execution_id)`** — every recorded step for the execution. Returns `(step_number, agent_id, tools_used, occurred_at)`; an empty result is what `sp_complete_execution` checks to block completing a step-less execution.

---

## Multi-tenant isolation and `SECURITY DEFINER`

All 5 procedures run as `sampler` (the schema owner), not as `runner`. Because of that, the migration that creates them also adds `ALTER TABLE ... FORCE ROW LEVEL SECURITY` on the 9 tenant-scoped tables and grants `runner` `EXECUTE` on the 5 procedures — without `FORCE`, `sampler`-as-owner would skip the `tenant_isolation` policy while running procedure bodies, silently breaking the isolation these procedures are supposed to preserve. `runner` doesn't lose any of its existing table privileges; this migration only adds `EXECUTE`. Full detail in `process.spec.md` § Technical context and § Implementation.
