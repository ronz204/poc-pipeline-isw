# Triggers & Audit — Reference

What each trigger under `drizzle/customs/triggers/` actually does, in plain language, without reading the SQL line by line. Design rationale, deferred decisions, and invariants live in `triggers.spec.md` (same folder) — this file only explains behavior.

---

## Business triggers

Six triggers enforce business rules or maintain derived state on the core domain. Each fires automatically on INSERT/UPDATE/DELETE — none is ever called manually.

| Trigger | Table | Event | Role |
|---|---|---|---|
| `trg_executions_set_finished_at` | `core.executions` | BEFORE UPDATE | Maintenance |
| `trg_executions_validate_transition` | `core.executions` | BEFORE UPDATE | Validation |
| `trg_executions_validate_attempt_number` | `core.executions` | BEFORE INSERT | Validation |
| `trg_execution_errors_fail_execution` | `trace.execution_errors` | AFTER INSERT | Maintenance |
| `trg_swarm_agents_validate_tenant` | `core.swarm_agents` | BEFORE INSERT | Validation |
| `trg_tasks_validate_swarm_active` | `core.tasks` | BEFORE INSERT | Validation |

### `trg_executions_set_finished_at`

**Maintenance.** When an execution's `status` moves to `completed` or `failed` and `finished_at` is still `NULL`, it gets set to `now()`. Saves every caller from having to remember to stamp `finished_at` on every terminal transition.

### `trg_executions_validate_transition`

**Validation.** Two independent checks on every UPDATE:

- Rejects the update if the row was already `completed` or `failed` and the new `status` differs — terminal states are final, an execution can never be reopened.
- Rejects the update if `finished_at` would end up earlier than `started_at`.

Both raise with `ERRCODE = check_violation` and a message naming the execution id and the offending values.

### `trg_executions_validate_attempt_number`

**Validation.** On INSERT, counts how many executions already exist for the same `task_id` and requires `attempt_number` to equal `count + 1` — retries for a task must be strictly consecutive (1, 2, 3, ...), never skipped or duplicated.

### `trg_execution_errors_fail_execution`

**Maintenance.** After a row is inserted into `trace.execution_errors`, updates the referenced execution's `status` to `failed` — but only if it isn't already `completed` or `failed`. If the execution is already terminal, the `UPDATE` matches zero rows and nothing happens; this is deliberate, so it never fights `trg_executions_validate_transition` (which would otherwise reject re-transitioning a terminal execution). The error row itself is always recorded regardless of whether the status update took effect.

### `trg_swarm_agents_validate_tenant`

**Validation.** `core.swarm_agents` is a pure junction table with no `tenant_id` column of its own and no RLS. On INSERT, the trigger looks up the `tenant_id` of the referenced swarm and the referenced agent and rejects the insert if they differ. This is what closes the multi-tenant isolation gap that the missing `tenant_id`/RLS would otherwise leave open on this one table.

### `trg_tasks_validate_swarm_active`

**Validation.** On INSERT, looks up the referenced swarm's `status` and `deleted_at` and rejects the insert if the swarm is soft-deleted (`deleted_at IS NOT NULL`) or `archived` — no new work can be created against a swarm that's no longer operational.

---

## Audit system

Fully independent from the business triggers above — a separate mechanism whose purpose is audit, security, and error recovery (not business-rule enforcement), so it isn't counted toward the six business triggers.

A single function, `trace.fn_log_audit_change()`, is reused by five triggers, one per audited table:

| Trigger | Table | Event |
|---|---|---|
| `trg_audit_swarms` | `core.swarms` | AFTER INSERT OR UPDATE OR DELETE |
| `trg_audit_agents` | `core.agents` | AFTER INSERT OR UPDATE OR DELETE |
| `trg_audit_tasks` | `core.tasks` | AFTER INSERT OR UPDATE OR DELETE |
| `trg_audit_executions` | `core.executions` | AFTER INSERT OR UPDATE OR DELETE |
| `trg_audit_users` | `auth.users` | AFTER INSERT OR UPDATE OR DELETE |

`auth.tenants` is not audited — it's the root of multi-tenant isolation, and no human actor exists yet at the moment a tenant is created.

### What each audit write records

For every INSERT/UPDATE/DELETE on an audited table, one row is inserted into `trace.audit_log`:

```
id           extensions.gen_random_uuid()
tenant_id    OLD.tenant_id (DELETE) or NEW.tenant_id (INSERT/UPDATE)
user_id      the resolved actor — see below
action       'created' / 'updated' / 'deleted'
entity_type  TG_TABLE_NAME (e.g. 'swarms', 'users')
entity_id    OLD.id (DELETE) or NEW.id (INSERT/UPDATE)
details      jsonb: { summary, before, after }
occurred_at  now()
```

`summary` is a short readable line (e.g. `"swarms creado (id=...)"`), not a full row dump. `before`/`after` are `to_jsonb(OLD)`/`to_jsonb(NEW)` with the `password` key stripped — the only column ever excluded, since `auth.users` is the only audited table that has one.

### Resolving the actor

`user_id` is `NOT NULL`, so the function has to resolve an actor before it can write the row:

1. Try `current_setting('app.current_user_id', true)` — set by the application via `TenantScope.setActor()` earlier in the same transaction.
2. If that's not set and the operation is an INSERT into `auth.users`, the new user audits themself (`NEW.id`) — a freshly created user has no `app.current_user_id` of their own yet.
3. Otherwise, fall back to the affected tenant's admin user, or its oldest user if it has no admin:
   ```sql
   SELECT id INTO v_actor
   FROM auth.users
   WHERE tenant_id = v_tenant_id
   ORDER BY (role = 'admin') DESC, created_at ASC
   LIMIT 1;
   ```
   This keeps every audited write from failing outright when a caller writes without having called `setActor()` first.

### Querying the history

`trace.fn_ver_historial_tabla(p_table_name text)` returns every recorded change for a given table:

```sql
SELECT a.id, a.user_id, a.action, a.entity_id, a.details, a.occurred_at
FROM trace.audit_log a
WHERE a.entity_type = p_table_name
ORDER BY a.occurred_at DESC;
```

For example, `SELECT * FROM trace.fn_ver_historial_tabla('swarms')` lists every create/update/delete ever recorded against `core.swarms`, most recent first.
