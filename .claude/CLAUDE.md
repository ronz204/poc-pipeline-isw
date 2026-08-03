# Swampert

Swampert is a platform that orchestrates and audits swarms of AI agents: it faithfully models what a multi-tenant system would look like if it tracked swarms, agents, tasks, executions, token costs, errors, and audit trails — without actually running any agents. It's the Project II submission for ISW-522: the data model is reused without structural changes from Project I, and the grading weight sits on the procedural layer (stored procedures, functions, triggers, auditing) plus a read-only dashboard over summary tables. Due: 2026-08-28.

## Knowledge base layout

This repo's documentation lives under `.claude/`, alongside the skill that acts on it, plus per-slice specs that live wherever the slice they describe makes sense.

- **`.claude/docs/`** (English) — engineering reference cross-checked against the actual codebase: what Swampert is, the rubric it's graded against, DB provisioning. No business/product framing, self-contained files. This is what grounds implementation work.
- **`.claude/rules/`** (English) — conventions that load automatically when a matching file is opened or edited, instead of being read on demand.
- **`.claude/skills/`** (project-scoped) — capabilities to reach for across tasks: `archivist`, `specifier`.
- **`<topic>.spec.md`** — a living contract for one bounded, cohesive slice of the system (e.g. `drizzle-db.spec.md`). No fixed location — Glob `**/*.spec.md` rather than assuming a path. Unlike a one-shot plan, a spec is never closed or deleted once implemented: it's edited in place as that slice's reality changes, and there's no separate `history/` log — the reasoning for a change belongs inline, in the section it affects.

**Precedence when a doc disagrees with the code:** the actual code always wins. Don't silently propagate a stale doc — flag the mismatch, and update the file only in the direction of improvement (never regress a doc just to match old content).

### `.claude/docs/` — the engineering reference

Maintained via the `archivist` skill: every claim is checked against the actual codebase, never carried over by assumption.

| File | Purpose | Consult when |
|---|---|---|
| `.claude/docs/overview.md` | What Swampert is, its multi-tenant domain model (swarms, agents, tasks, executions, costs, errors, audit logs), the observability/auditing/governance problem it solves, and explicit non-goals (no agent execution, no LLM calls) | Scope questions, "why does this entity exist" questions |
| `.claude/docs/approach.md` | Requirements and constraints from the official Project II assignment: point distribution (100 pts), what each component demands (procedures, functions, triggers, auditing, summary tables, dashboard, documentation, oral review), milestone schedule | Deciding whether a task satisfies the rubric, sequencing work against weeks 9-14 |
| `.claude/docs/database.md` | Provisioning: the three schemas (`auth`/`core`/`trace`), column conventions, the `pgcrypto` extension, the three Postgres roles (`sampler`/`runner`/`backuper`), the `FORCE` RLS pattern, and the split between modeling (DDL) and granting (DCL) migrations | Any migration, new table, role/permission, RLS policy |

`approach.md` is still in Spanish, pending translation to match the other two — don't treat that as the established language for new `.claude/docs/` content.

### `.claude/rules/` — conventions applied automatically

- **`coding.md`** — global (no `paths:`), applies to every file regardless of language. Language-agnostic clean-code conventions: coupling/cohesion smells, SOLID, classic smells, and when a design pattern is worth reaching for vs. misused.
- **`engine.md`** — loads on `projects/swampert-engine/**`. TypeScript on Bun (ElysiaJS + Drizzle over Postgres): classes over standalone functions (with the Elysia-plugin/Drizzle-schema exceptions where the framework's own idiom wins), file naming (`.plugin.ts`/`.helper.ts`/`.element.ts`/`.seeder.ts`/`.client.ts`), path aliases, env validation via `zod`, and data-layer conventions (`TenantScope`, shared column/policy helpers).
- **`client.md`** — loads on `projects/swampert-client/**`. TypeScript on Vite/Bun, Vue 3 Composition API only: classes for service-style code vs. composables staying functions (Vue's own idiom), the `erasableSyntaxOnly` constraint on how classes can be written here (no parameter properties, no `enum`), path aliases, and deferring state-management libraries until composables genuinely stop being enough.

Read the rule file directly rather than relying on these summaries when touching a matching path — each loads itself automatically.

### `.claude/skills/` — project-scoped capabilities

- **`archivist`** — creates and updates everything above plus every `<topic>.spec.md`: `.claude/docs/`, `.claude/rules/`, new skills, and specs. Invoke it whenever documenting an architecture decision, recording a convention, scaffolding a new skill, or writing/updating a spec before implementing something non-trivial — it always inspects the real codebase before writing, never documents from memory or from conversation alone. Writes every artifact from a matching skeleton under its own `references/*.template.md`; the spec convention itself is fully defined in `references/spec.template.md`, not spread across a separate methodology doc.
- **`specifier`** — the information-gathering step before a robust spec: investigates a slice's real implementation, checks it against `.claude/docs/`/`.claude/rules/`, and asks the targeted questions code alone can't answer (intent, invariants, deferred decisions), then hands the result to `archivist` to write. Invoke it before creating or hardening a `<topic>.spec.md` — it never writes into the spec file itself.

### `<topic>.spec.md` — living per-slice specs

Spec-Driven Development at the granularity of one cohesive capability (a "slice"), not one source file and not a single day's batch of tasks — e.g. `drizzle-db.spec.md`, `dashboard.spec.md`. One spec per slice: 8 required sections (objective, scope, technical context, implementation, config/secrets, acceptance criteria, how to test, risks/edge cases), defined in full in `.claude/skills/archivist/references/spec.template.md`. A spec is edited in place for the life of the slice it describes — it's never closed, superseded, or deleted once the first implementation lands, and there's no append-only decision log alongside it.

## Permissions

`.claude/settings.json` denies reading `.env*`/`secrets/**` and blocks `git push`/`git pull` outright — don't attempt to work around either; ask the user to run those directly instead.

## Repo layout

Monorepo, two deployable projects under `projects/`:

- **`projects/swampert-engine`** (`package.json` → `swampert-api`) — Bun + ElysiaJS + Drizzle ORM on Postgres. Owns the data model, migrations (`drizzle/`), and the business logic exposed via stored procedures/functions.
- **`projects/swampert-client`** — Vue 3 + Vite SPA. Vue Router, Tailwind v4, Chart.js for the analytics dashboard.

`services/` holds local infra (Postgres) via `compose.yml`.
