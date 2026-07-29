# Swampert

Swampert is a platform that orchestrates and audits swarms of AI agents: it faithfully models what a multi-tenant system would look like if it tracked swarms, agents, tasks, executions, token costs, errors, and audit trails — without actually running any agents. It's the Project II submission for ISW-522: the data model is reused without structural changes from Project I, and the grading weight sits on the procedural layer (stored procedures, functions, triggers, auditing) plus a read-only dashboard over summary tables. Due: 2026-08-28.

## How to work on this project

- Before non-trivial work touching the data model, roles/permissions, RLS, or rubric scope, check the relevant file in `contexts/` (table below) to ground the work in the team's existing thinking.
- **`contexts/` is reference, not absolute truth.** It's the plan as currently understood — useful to have on hand, not a spec to follow blindly. If the actual code disagrees with a `contexts/` doc, trust the code and flag the mismatch instead of silently propagating a stale doc. If you or the user land on a decision that's genuinely better than what a doc says, take the better decision — changes to what's documented are fine, but only in the direction of improvement, never a regression just to match old context.
- When a decision documented in `contexts/` changes, update the corresponding file so it keeps reflecting current reality — usually the user will ask explicitly, but proactively flag drift you notice.
- Context docs are written in Spanish — match that when editing them.

| File | Purpose | Consult when touching |
|---|---|---|
| `contexts/overview.md` | What Swampert is, what the product is about (multi-tenant: tenants, swarms, agents, tasks, executions, steps, costs, errors, auditing) | Scope questions, "why does this entity exist" questions |
| `contexts/problems.md` | The real problem it solves (observability, auditing, multi-tenant governance) and what's deliberately out of scope (no agent execution, no LLM calls) | Prioritization, justifying what each component is for during the oral review |
| `contexts/concepts.md` | Theory behind the modeling: multi-tenancy, Row-Level Security, advanced types (JSONB/ARRAY/ENUM/UUID), `pgcrypto`, normalization, partitioning, indexing, auditing/traceability | Before justifying why the model is designed the way it is — key for the oral review |
| `contexts/database.md` | Provisioning: the three schemas (`auth`/`core`/`trace`), column conventions, the `pgcrypto` extension, the three Postgres roles (`sampler`/`runner`/`backuper`), the `FORCE` RLS pattern, and the split between modeling (DDL) and granting (DCL) migrations | Any migration, new table, role/permission, RLS policy |
| `contexts/approach.md` | Requirements and constraints from the official Project II assignment: point distribution (100 pts), what each component demands (procedures, functions, triggers, auditing, summary tables, dashboard, documentation, oral review), milestone schedule | Deciding whether a task satisfies the rubric, sequencing work against weeks 9-14 |
| `contexts/planning.md` | Task-planning methodology: the 8-section spec template (Objetivo, Alcance, Contexto técnico, Implementación, Config/secretos, Criterios de aceptación, Cómo probar, Riesgos/edge cases) every `*.plan.md` file follows | Before starting any non-trivial implementation — search the repo for a relevant `*.plan.md` (files aren't pinned to a fixed path); if none exists and the work isn't trivial, propose writing one using this template before coding |

## Repo layout

Monorepo, two deployable projects under `projects/`:

- **`projects/swampert-engine`** (`package.json` → `swampert-api`) — Bun + ElysiaJS + Drizzle ORM on Postgres. Owns the data model, migrations (`drizzle/`), and the business logic exposed via stored procedures/functions.
- **`projects/swampert-client`** — Vue 3 + Vite SPA. Vue Router, Tailwind v4, Chart.js for the analytics dashboard.

`oldversion/` holds the numbered SQL migrations from an earlier iteration of the model (schemas, tables, security, seeders, clustering) — historical reference from Project I's modeling, not active code for the current project. See `contexts/database.md` for the conventions currently in effect for schemas and roles.
