---
name: specifier
description: Use before writing or substantially revising any `<topic>.spec.md` file. Gathers the information a robust spec actually needs — investigating the real implementation, checking it against existing `.claude/docs/`/`.claude/rules/` content, and asking the user targeted questions about intent, boundaries, invariants, and open decisions — then hands that material off to the `archivist` skill to write into the spec. Trigger whenever the user wants to "spec out" a slice, flesh out or harden an existing spec, or says things like "vamos a especificar X", "necesito robustecer el spec de Y", "hagamos el spec de este slice", or "¿qué le falta a este spec?". Never writes a `.spec.md` file directly — that's `archivist`'s job; this skill only produces the grounded material `archivist` needs.
---

# Specifier

Code shows what a slice currently does. It doesn't show why the slice exists, what's deliberately out of scope, what must never break, or what's intentionally left undecided — those only come from asking. This skill's entire job is producing that missing half so the spec `archivist` writes is grounded and complete, not a paraphrase of the source code with the important parts guessed at.

Splitting this from `archivist` is a deliberate SRP call: this skill's reason to change is "did we ask the right questions and find the right conflicts" — `archivist`'s reason to change is "does the artifact land in the right shape." Keeping them separate means the writing conventions (the 8-section template, English-only, no product framing) stay consistent regardless of who's answering questions on a given day.

---

## Step 0 — Read what already exists for this topic

Before asking the user anything, find out what's already known:

- Glob `**/*.spec.md` for a file matching this topic — specs have no fixed location, don't assume one doesn't exist. If it already has content, read it in full; every question below should be about a genuine gap or an update, not something already answered.
- If no spec exists yet for this topic, don't create the file — confirm the topic's name and boundary with the user first (writing the file itself is `archivist`'s step, once there's real content to put in it).
- Because a spec is a living document with no separate `history/` log (see `.claude/skills/archivist/references/spec.template.md`), there's no decision trail to read beyond the spec's current text — whatever reasoning survived a past revision is whatever's still written in the relevant section today.

## Step 1 — Investigate the real implementation

Same discipline `archivist` applies at its own Step 0: find and read the actual source that implements this slice — grep by its feature/path-alias name, walk its folder, read the whole file rather than an excerpt. Don't infer behavior from a filename or a related doc's description.

While reading, actively check the implementation against:
- Any `.claude/docs/*` claim that describes this slice (`overview.md` for domain scope, `approach.md` for rubric requirements, `database.md` for schema/RLS/role conventions).
- Any `.claude/rules/*` convention that should apply to it — `coding.md` globally, plus `engine.md` or `client.md` depending on which project the slice lives in (e.g. the RLS/tenant-scoping pattern, the classes-over-functions convention and its framework exceptions).

Note every mismatch found — a doc that says one thing while the code does another is exactly the kind of gap a robust spec exists to close, not something to quietly resolve in either direction.

## Step 2 — Ask what code alone can't answer

Map each answer to the section of `spec.template.md` it will feed. For each of the following, either confirm it directly from what Step 1 found, or ask the user — don't guess:

- **Objective** — why does this slice exist and what's its observable contract, in a sentence or two of domain language (not an implementation summary)? Feeds the spec's **Objective**.
- **Scope & deferred work** — what's explicitly *not* this slice's job, especially anything a future contributor could plausibly assume belongs here? What's intentionally postponed, and what event or threshold would trigger deciding it (a scaling point, a feature-priority call, a rubric milestone)? Feeds **Scope** — there's no separate "open questions" section, so a deferred item and why it's safe to defer both belong there.
- **Invariants & risks** — what must hold no matter how the implementation changes later, and what could fail silently if not made explicit now (an edge-case input, an RLS/tenant-scoping assumption, a volume concern)? Feeds **Risks / edge cases** — usually the highest-value part of the spec, since it's the part that actually gets checked against future changes.
- **Acceptance criteria** — how would someone verify this spec is satisfied, as a binary checklist? When the slice touches a rubric component, this should name the specific `approach.md` requirement it covers, not just "implemented." Feeds **Acceptance criteria**.
- **How to test** — the exact command, call, or manual flow to verify it, with expected input/output. Feeds **How to test**.

Ask in a short, focused batch (`AskUserQuestion` when the choices are concrete and enumerable) rather than dumping the whole list at once — a spec built from five rushed answers is worse than one built from two well-considered ones, continued next turn if needed.

## Step 3 — Reconcile conflicts explicitly

Any mismatch found in Step 1, or any place where the user's answer contradicts an existing doc/rule/the spec's own current text, gets surfaced and resolved with the user before it goes anywhere — never silently pick the code's version or the doc's version. Once resolved, that reasoning goes straight into the relevant section of the spec itself — there's no `history/` entry to write separately, so don't let the resolution stay only in this conversation.

## Step 4 — Hand off to archivist

Once objective, scope, technical context, invariants/risks, and acceptance criteria are each either confirmed from code or answered by the user, package the result and invoke `archivist` to write it: a new or updated `<topic>.spec.md` via `references/spec.template.md`. This skill's job ends at producing that material — it never writes the `.spec.md` file itself, even when the answer seems obvious enough to just write down directly.

---

## Non-goals

- Don't re-ask about anything already settled in the topic's existing `.spec.md` — Step 0 exists specifically to prevent that.
- Don't write the `.spec.md` file directly, even to save a round-trip — the separation from `archivist` is what keeps every spec's shape consistent, not a formality to skip when it's inconvenient.
- Don't force every field to a firm answer before handing off. "This is intentionally undecided until X" is a complete, valid answer for Scope's deferred-work part — manufacturing a premature decision just to fill the section produces a spec that lies about its own certainty.
- Don't spec out a slice that's a single trivial file with no invariant worth protecting — per `coding.md`'s own non-goals, this system's ceremony pays for itself against real complexity, not by default.
