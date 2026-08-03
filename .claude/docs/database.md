# Swampert — Database Provisioning

> What to run against a fresh Postgres instance so it's ready to receive migrations: schema conventions, the single required extension, the three Postgres roles, the Row-Level Security pattern that protects multi-tenant isolation, and how modeling and permissions are split across migrations. Precedes any domain migration, and applies the same regardless of where the instance runs — local development or production.

---

## 🧱 Schema conventions

Swampert organizes its tables into **three schemas**, each with a distinct reason to exist and no overlap between them:

| Schema | Contains | Why it's separate |
|---|---|---|
| `auth` | `tenants` (the tenant), `users` | Identity: which client organization is which, and who can authenticate inside it. `tenants` is the root of multi-tenant isolation — everything else hangs off it. |
| `core` | `swarms`, `agents`, `tasks`, `executions` | The stable business domain: what exists (swarms, agents, tasks) and what ran. Changes at the same pace as the rest of the model. |
| `trace` | `execution_steps`, `token_costs`, `execution_errors`, `audit_log` | Everything that grows without bound and exists to observe: the step-by-step detail of an execution, its cost, its errors, and the audit trail of configuration changes. It's the highest-volume schema and the natural partitioning candidate (see `concepts.md` § Partitioning). |

Two multi-tenant isolation rules, simple but with no exceptions:

- **`tenants` does not carry `tenant_id`.** It's the root of isolation, not a resource that belongs to a tenant — everything else does carry it.
- **Every other tenant-scoped table carries `tenant_id NOT NULL`** referencing `auth.tenants.id`. There are 9 in total: `auth.users`, the 4 in `core`, and the 4 in `trace`. The `trace` tables carry it denormalized (not resolved via `JOIN` to `executions`) for the same RLS performance reason documented in `concepts.md` § Row-Level Security.

### Column types and patterns

Three conventions repeat across the model's 10 tables, with no exceptions:

| Convention | Rule | Why |
|---|---|---|
| **Identifiers** | `UUID` as PK, generated as `uuidv7()` in the application (`drizzle/database/drizzler.client.ts`) | In a multi-tenant system, a sequential ID (`SERIAL`/`BIGSERIAL`) leaks business volume to other client organizations on the same system — anyone can estimate how many rows exist by counting gaps between their own IDs. |
| **Timestamps** | `TIMESTAMPTZ`, never bare `TIMESTAMP` | `TIMESTAMPTZ` stores the actual instant (normalized to UTC internally) and converts it to the client's zone on read. `TIMESTAMP` without a time zone is ambiguous as soon as more than one zone is involved — server, backend, end user — which is exactly the case here. |
| **Deletion** | `ON DELETE RESTRICT` on every FK + soft delete via `deleted_at TIMESTAMPTZ NULL` | `RESTRICT` makes deleting a row with dependents fail explicitly instead of silently cascading. Soft delete is the actual "delete" mechanism from the application: `deleted_at` gets set, the row never physically disappears, and application queries filter `WHERE deleted_at IS NULL`. Between the two, the model never loses history irreversibly or by accident. |

---

## 🧩 Required extension

Swampert needs a single extension, enabled in the first migration before a single table is created:

| Extension | For | Availability |
|---|---|---|
| `pgcrypto` | Provides `gen_random_uuid()`. | Part of `contrib`, included in the official `postgres` image — no extra steps, no custom image or `Dockerfile`. |

> **What actually exercises it:** `auth.users.password` hashing lives in the application (`Bun.password`, see `concepts.md` § Password hashing) — it does not use `pgcrypto`'s `crypt()`/`gen_salt('bf')`. Business-row IDs are also generated in the application (`uuidv7()`, see `drizzler.client.ts`) rather than via a column `DEFAULT`; no `id` column in `drizzle/elements/*.ts` declares `.default(sql\`gen_random_uuid()\`)`. The one place `pgcrypto` is genuinely exercised today is inside Postgres itself: the audit trigger function (`trace.fn_log_audit_change`, see `AUDITORIA`) calls `extensions.gen_random_uuid()` directly to generate each `trace.audit_log` row's id, because that row is written by a trigger running entirely in the database, not by application code that could call `uuidv7()`.

```sql
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto SCHEMA extensions;
```

There's no other extension in the model — unlike projects that need semantic or full-text search, Swampert has no such requirement, so the official Postgres image is enough unmodified.

---

## 🧬 Migrations: modeling and permissions kept separate

Migrations are flat, numbered `.sql` files (`NNNN-description.sql`), applied by the project's own runner with idempotency by file name and an independent transaction per migration — none of that changes here, it's an already-established convention.

**What is adopted from Kelsen's provisioning: every schema change is split into (at least) two migrations — modeling (DDL) and permissions (DCL).** Instead of a single migration that creates tables and grants privileges in the same file, the pattern is:

```sql
-- 0004-modeling-core.sql: structure only
CREATE SCHEMA "core";
CREATE TABLE "core"."swarms" ( ... );
CREATE TABLE "core"."agents" ( ... );
-- ... rest of core's tables and constraints

-- 0005-granting-core.sql: permissions only, on what already exists
GRANT USAGE ON SCHEMA core TO runner;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA core TO runner;
ALTER DEFAULT PRIVILEGES FOR ROLE sampler IN SCHEMA core
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO runner;
```

**Why split it:** it leaves the structural change (what exists) and the permission change (who can touch it) as two separately reviewable units, with the grant history auditable on its own — a change that only adjusts privileges never gets mixed with one that adds a column. It's a working convention, not a rigid rule: the exact name (`modeling-<feature>` / `granting-<feature>`) can be adjusted; what stays fixed is the underlying idea — **DDL and DCL never share a migration.**

---

## 🔐 Postgres roles

Swampert uses three roles, each with a distinct purpose and privilege set:

| Role | Purpose | Privileges | Runs where |
|---|---|---|---|
| `sampler` | Owner of Swampert's three schemas and all their objects. Applies every migration, modeling and permissions alike. | The only role with `CREATE` on the `swampert` database — everything it creates (schemas, tables, functions) is automatically owned by it. Bypasses RLS by being the owner — precisely why it never serves traffic. | Exclusively the migration runner, never the application process. |
| `runner` | The only role the backend runs as. | **Current phase** (before procedures exist): direct `SELECT`/`INSERT`/`UPDATE`/`DELETE` on the tables of all three schemas. Explicit `NOBYPASSRLS` — every write still goes through RLS policies regardless, see below. | The backend (ElysiaJS), in any environment. |
| `backuper` | Periodic backup of the whole database. | Only `CONNECT` plus whatever `pg_dump` needs to read schema and data. No `INSERT`/`UPDATE`/`DELETE`, no `EXECUTE`. Explicit `NOBYPASSRLS`. | The backup process, never the backend or an interactive human. |

### Two-layer provisioning: manual bootstrap + granting migrations

The three roles are **not** created by a migration — there's a chicken-and-egg problem: the migration runner connects as `sampler`, so `sampler` has to exist *before* the first migration can run. That's why they're created once, by hand, against the fresh instance, with [`projects/swampert-engine/drizzle/bootstrap.sql`](../../projects/swampert-engine/drizzle/bootstrap.sql) — applied with a superuser (or instance-admin) connection, never with the runner or any of the three roles it creates:

```sql
-- Roles, created idempotently (safe to re-run the script)
CREATE ROLE sampler  WITH LOGIN PASSWORD '...' NOBYPASSRLS;
CREATE ROLE runner   WITH LOGIN PASSWORD '...' NOBYPASSRLS;
CREATE ROLE backuper WITH LOGIN PASSWORD '...' NOBYPASSRLS;

-- All three can connect and use pgcrypto...
GRANT USAGE ON SCHEMA extensions TO sampler, runner, backuper;
GRANT CONNECT ON DATABASE swampert TO sampler, runner, backuper;

-- ...but only sampler can create new objects
GRANT CREATE ON DATABASE swampert TO sampler;
```

Notice what `bootstrap.sql` does **not** do: it doesn't create `auth`/`core`/`trace`, and it doesn't give `runner` or `backuper` a single privilege on those schemas. That's intentional — the bootstrap only solves cold start (that the roles exist, and that `sampler` can create things). Everything else happens afterward, once migrations are running:

1. **Ownership by creation, not by explicit `AUTHORIZATION`.** Since only `sampler` has `CREATE` on the database, every `CREATE SCHEMA`/`CREATE TABLE` in a modeling migration (`000N-modeling-*.sql`) is automatically owned by it — the owner of a Postgres object is whoever executes the statement that creates it, and whoever runs migrations is always `sampler`.
2. **`runner` and `backuper` access is only granted in the granting migrations** (`000N-granting-*.sql`, previous section). Until that migration runs, neither can see a single row of `auth`/`core`/`trace`, even though they can already connect to the database from the bootstrap.

In other words: **ownership is entirely `sampler`'s from the bootstrap on, and every other role's access is built migration by migration, never all at once.**

**Why `runner` has direct `INSERT`/`UPDATE`/`DELETE` today, and why that's going to change:** Project II requires that every business write end up going through a stored procedure that validates and transacts — not a loose statement from the backend. That's the structural goal, but the procedures and functions don't exist yet (they land in the week 9-11 milestones, see `approach.md`), and the backend needs to be able to write in the meantime to be developed and tested. That's why, in this phase, `runner` gets direct `SELECT`/`INSERT`/`UPDATE`/`DELETE` on the tables of all three schemas — a deliberate, temporary concession, not the final architecture.

Once `core`/`trace` procedures and functions are defined as `SECURITY DEFINER` (owned by `sampler`), the plan is to **revoke `runner`'s direct `INSERT`/`UPDATE`/`DELETE`** and leave it with only `SELECT` + `EXECUTE` on those procedures — only then does the academic requirement ("the whole flow goes through a procedure") become structurally guaranteed by the database, not just by convention. Until that happens, nothing stops an endpoint from writing with a loose statement; it's a known, accepted gap while the procedural layer doesn't exist yet, not an oversight.

Important: this concession does **not** weaken multi-tenant isolation. RLS via `ENABLE ROW LEVEL SECURITY` already governs any role that isn't the table's owner — `runner` is never the owner (`sampler` is), so the `tenant_isolation` policy evaluates the same on every `INSERT`/`UPDATE`/`DELETE` from `runner`, with or without `FORCE`. `FORCE` only starts to matter the day writing code runs as `sampler` (the future `SECURITY DEFINER` procedures) — see the call-out in the RLS section below.

**Non-negotiable usage rules:**

- `sampler` runs exclusively when applying migrations — never in the backend process or the backup process.
- `runner` is the only credential in the backend's environment variables.
- `backuper` is the only credential for the backup process — never used to debug or for manual queries.
- No role has `BYPASSRLS`. If a process ever needs to cross data between organizations in the future (e.g. a platform-wide aggregate report), it's solved with an explicit, audited `SECURITY DEFINER` function — never by giving `BYPASSRLS` to a general-purpose connection role.
- `ALTER DEFAULT PRIVILEGES` is executed as `sampler`, so any new table or function created by a future migration automatically inherits the correct permissions.

---

## 🛡️ Row-Level Security: application pattern

RLS with `FORCE` is, here, the central isolation mechanism — not a redundant second layer. Since procedures and functions run `SECURITY DEFINER` with `sampler` as owner (previous section), without `FORCE ROW LEVEL SECURITY` the owner itself would bypass the policy while executing business logic, and isolation between organizations would stop existing in practice even though the policy exists in the catalog.

> **Actual state today:** the generated modeling migrations only have `ENABLE ROW LEVEL SECURITY` — neither `drizzle-orm@1.0.0-rc.4` nor `drizzle-kit` emit `FORCE` yet from the DSL (`table.withRLS(...)`). This isn't a problem while the only writer is `runner` (a non-owner, already covered by `ENABLE`) — it only becomes necessary once the `SECURITY DEFINER` procedures owned by `sampler` mentioned above exist. Adding it then will require a raw SQL statement (`ALTER TABLE ... FORCE ROW LEVEL SECURITY`) outside Drizzle's DSL.

Each of the 9 tenant-scoped tables (`auth.users`, the 4 in `core`, the 4 in `trace`) follows the same three-step pattern:

```sql
ALTER TABLE <schema>.<table> ENABLE ROW LEVEL SECURITY;
ALTER TABLE <schema>.<table> FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON <schema>.<table>
  USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid)
  WITH CHECK (tenant_id = current_setting('app.current_tenant_id', true)::uuid);

CREATE POLICY backup_read ON <schema>.<table>
  FOR SELECT TO backuper
  USING (true);
```

- `auth.tenants` carries no tenant policy — it's the root of isolation, not a resource belonging to a tenant.
- `tenant_id NOT NULL` is the leading column in every tenant-scoped table's composite indexes, because every real query already arrives filtered by organization.
- The second argument `true` of `current_setting(...)` (`missing_ok`) is mandatory: without it, a session with no `app.current_tenant_id` set (like `backuper` running `pg_dump`) makes the function raise an exception instead of returning `NULL`, and that exception aborts the query before the `backup_read` policy gets a chance to grant access via `OR`. With `missing_ok`, `tenant_isolation` simply evaluates to `NULL`/false for that session and `backup_read` takes over.

### `SET LOCAL`, never `SET SESSION`

Tenant context is set **within the same transaction** the procedure or query runs in:

```sql
BEGIN;
SET LOCAL app.current_tenant_id = '<authenticated organization's uuid>';
-- CALL to a procedure, or a read SELECT
COMMIT;
```

`SET SESSION` stays pinned to the physical connection if the backend uses connection pooling in transaction mode — a real isolation failure between organizations, not a theoretical one, if that connection gets reused for another tenant. `SET LOCAL` clears at transaction end regardless of pooling. This `BEGIN` → `SET LOCAL` → `CALL`/`SELECT` → `COMMIT` sequence is implemented as an explicit transaction wrapper in the backend, never left as each endpoint's own responsibility.
