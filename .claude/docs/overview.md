# Swampert — Overview

Swampert models and audits multi-tenant swarms of AI agents — swarms, agents, tasks, executions, costs, errors, and audit trails — without executing any agent or calling an LLM.

---

## What Swampert is

Swampert is the system of record for an organization running teams of AI agents instead of a single assistant: which agent did what, in what order, how much it cost in tokens, where it failed, and who inside the tenant is allowed to see that information.

It behaves like a control panel and ledger combined, but only from the data side — it does not run the agents it tracks. Every entity in the model (a swarm executing a task, an agent taking a step, a token cost being incurred) is inserted directly rather than produced by a real agent run, so the system can be reasoned about, queried, and audited exactly as if it were live.

## Domain model (multi-tenant)

Every tenant (a client organization) owns its own instance of the same entity graph, isolated from every other tenant on the same platform:

| Entity | Represents |
|---|---|
| Swarm | A group of agents collaborating to resolve a task |
| Agent | An individual unit within a swarm, with its own configuration and assigned tools |
| Task | The concrete work requested from a swarm |
| Execution | One attempt at resolving a task (retries produce multiple executions) |
| Execution step | The step-by-step detail of what an agent reasoned and did within an execution |
| Token cost | What an execution cost in tokens, for spend control |
| Execution error | What failed, at which step, and why |
| Audit log | Who — human or agent-driven change — did what, and when |

## The problem

Organizations running agent swarms lose visibility and control over what those agents do, what they cost, and who is accountable for what. This splits into three concerns:

- **Observability** — what happened, and in what order.
- **Auditing** — who did it, and when.
- **Multi-tenant governance** — is one tenant's data provably isolated from another's on the same platform.

Without a system built to answer these, an organization is operating blind: trusting that the agents behaved correctly, with no way to verify it, audit it, or intervene when something breaks or spend spikes.

## How Swampert addresses it

1. **Tenant isolation** — each tenant sees only its own swarms, agents, executions, and costs; no tenant can see another's data even by accident, regardless of sharing the same platform.
2. **Step-by-step traceability** — every execution is recorded as an ordered sequence of steps, so what an agent reasoned and did, in what order, and with which tools, can be reconstructed exactly.
3. **Cost control** — every execution carries its token cost, so a tenant can see what each kind of task costs to resolve with AI and detect anomalies.
4. **Error tracking** — a failure leaves a clear trail of which step it occurred at and why, instead of a swarm that simply "didn't work."
5. **Human action auditing** — in addition to auditing agents, Swampert records which human users changed system configuration (creating an agent, modifying a swarm, etc.), so both sides of accountability are covered.
6. **A single dashboard** — this data is only useful if it can be queried without writing SQL by hand; the dashboard filters and explores it by tenant, date, task, and agent.

---

## Non-goals

Swampert does not execute real AI agents and does not call any LLM. It models and audits what that ecosystem would look like from the data side only — who did what, what it cost, and who can see it. Real agent execution is deliberately out of scope for this project.
