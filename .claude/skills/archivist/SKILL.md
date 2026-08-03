---
name: archivist
description: Use whenever creating or updating anything in this project's Claude Code knowledge base — reference docs, rules under `.claude/rules/`, skills under `.claude/skills/`, or a living spec for a bounded slice of the system (any `<topic>.spec.md` file). Trigger this any time the user asks to document architecture, write up a decision, record a convention, scaffold a new skill, or write/update a spec before implementing something non-trivial — even without saying "documentation", e.g. "dejemos esto anotado", "hagamos un spec para X antes de tocar código", "turn this into a skill", "agreguemos esta convención a las reglas", "write up the spec for Y". Always inspect the actual project (code, existing docs, existing conventions) before writing anything; never document from memory or from the conversation alone.
---

# Archivist

Creates and updates every artifact in this project's Claude Code knowledge base: reference docs, rules, skills, and living specs. What makes this different from writing any one of those from scratch is threefold — every claim is grounded in the actual project instead of assumption, every artifact lands in the right *kind* of file instead of getting crammed into whichever one is open, and every kind has a matching skeleton in `references/` so its shape stays consistent across instances instead of being re-derived from prose each time.

This skill is deliberately project-agnostic: it doesn't assume a fixed doc layout or a fixed stack — Step 0 and Step 1 exist specifically to make you discover this project's actual conventions instead of importing ones from a different project. The spec convention itself (Step 4) is fixed and self-contained in `references/spec.template.md`, not something to rediscover per project.

---

## Step 0 — Read before you write

Never write or edit any of these from memory, from what the user just said, or from what an older doc says. Read the actual project first.

- If the artifact concerns part of the codebase, find and read the relevant source — actual files, actual migrations, actual config — not a description of them from earlier in the conversation.
- If it concerns infrastructure (roles, permissions, provisioning, deployment), check the actual provisioning scripts/migrations, not just what was decided in conversation — decisions drift from implementation.
- If it's a spec (`<topic>.spec.md`) for a slice that already exists, read what's actually there before updating it, so the spec doesn't contradict or re-litigate something already settled without saying so.
- If the user references a decision made earlier in chat ("ya cambiamos a X", "we already decided Y"), verify it landed in the actual project before documenting it as current. If it hasn't landed yet, say so and ask whether to document it as current or as planned/intended.
- Skim what already exists in this project's docs, rules, skills, and any `*.spec.md` files so you don't duplicate or contradict something already documented elsewhere. Use Glob (`**/*.spec.md`, project doc folders) rather than assuming a fixed path — see Step 1.

If the actual project contradicts an existing doc, or contradicts what the user just described, don't silently resolve it — surface the conflict and let the user decide which one is current.

---

## Step 1 — Figure out what kind of artifact this is, and where it lives

This project always has four kinds of knowledge-base artifact. Three have a fixed, harness-level location (rules and skills are a Claude Code mechanism, not an app convention). The fourth — docs — does not: its actual location is a per-project decision you have to discover, not assume.

| Content is... | Goes in |
|---|---|
| Stable reference material: architecture, domain concepts, provisioning facts, cross-cutting conventions — read occasionally, not applied on every edit | This project's existing docs location (see below) |
| A convention that must be **applied every time** a certain kind of file is written or edited (schema conventions, a style rule, a pattern that must be repeated) | `.claude/rules/<topic>.md`, scoped via `paths:` frontmatter |
| A capability Claude Code should reach for across many tasks, potentially with bundled scripts/templates/references | `.claude/skills/<name>/SKILL.md` |
| A living contract for one bounded, cohesive slice of the system — its scope, implementation, and current state | `<topic>.spec.md` — see Step 4, `references/spec.template.md` is self-contained and fixed for this project |

**Finding the docs location.** Don't default to a fixed path like `.claude/docs/` or `docs/` — different projects put curated reference docs in different places (a `contexts/` folder, a `docs/` folder, inline in `.claude/CLAUDE.md`, etc.). Before writing a doc:
1. Check `.claude/CLAUDE.md` (or `CLAUDE.md`) for a table or section naming the docs location.
2. If none, Glob for existing doc-like folders (`docs/**`, `contexts/**`, `.claude/docs/**`) and follow whichever one is already populated.
3. If truly nothing exists yet, ask the user where this project wants its docs to live rather than inventing a new location — a project should have exactly one docs home, not one per skill invocation.

The doc-vs-rule line is about repetition (read occasionally vs. applied every time a matching file is touched). The rule-vs-skill line is about surface: a rule injects context automatically into whatever's already happening; a skill is a capability the main session pulls in deliberately, potentially with bundled scripts/references/assets. The doc-vs-spec line is about grain and ownership: a doc is cross-cutting reference material spanning the whole project; a spec is scoped to one cohesive slice, but — unlike a one-shot pre-implementation plan — is never closed or deleted once implemented. It stays living, edited in place as that slice's reality changes (see Step 4).

If content doesn't cleanly fit an existing file, propose either a new section in the closest existing doc or a new file following the same naming/structure pattern already in use — don't force it into an unrelated file just to avoid creating one.

---

## Use the matching template

Every artifact kind above has a fill-in skeleton in `references/`: `docs.template.md`, `rule.template.md`, `skill.template.md`, `spec.template.md`. Read the one that matches before writing, and fill it in rather than re-deriving the shape from the prose in the steps below each time — the templates carry the structure, the steps below carry the reasoning behind that structure.

`spec.template.md` is the odd one out: for docs/rules/skills, this file (SKILL.md) carries the reasoning and the `references/*.template.md` carries only the shape. For specs, `references/spec.template.md` carries both — it's self-contained by design (see Step 4), so read it in full rather than relying on the summary below.

---

## Step 2 — Writing conventions for docs and rules

These are general engineering-writing defaults. They yield to whatever this project's own docs/rules already demonstrate — check a couple of existing files before writing the first line, and match what's already there rather than what's below, if the two disagree.

- **Match the project's existing language.** Don't default to English — check what the docs/rules you're adding alongside are already written in, and match it. A project's `CLAUDE.md` sometimes states this explicitly; if so, that wins.
- **Pure technical POV.** Prefer stripping product pitch, ROI framing, competitive positioning, sales language, business/legal framing from engineering reference docs. If a business or academic requirement drives an engineering decision (e.g. a rubric requirement shaping a schema choice), state the *engineering implication*, not just the external rationale — unless the project's own docs already mix the two deliberately.
- **Self-contained files.** Docs generally shouldn't lean on "see X.md" to make sense — each should stand alone. Rules may reference a doc once if the split genuinely creates a dependency — keep it to the minimum, prefer restating a short fact over adding a pointer.
- **Plain section headers**, no emoji, unless the project's existing docs already use emoji headers — match, don't impose.
- **Tables** for comparisons, option trade-offs, risk/complexity summaries.
- **Fenced code blocks** for SQL, JSON, config snippets, ASCII diagrams — never describe a schema or query in prose when a code block can say it exactly.
- **Explain why, not just what.** A convention stated without its reasoning gets silently violated the first time someone doesn't see why it matters.
- **Length:** docs tend to work best around ~100–200 lines — a section growing past that is a sign it belongs in a more specific file. Rules can run longer since they only load conditionally, but stay scoped to one concern.
- **Non-goals sections earn their place** when a scope boundary is easy to violate by accident.

### Rule mechanics

`.claude/rules/<name>.md` loads automatically when Claude Code reads a file matching the `paths:` glob patterns in the frontmatter — same priority as `CLAUDE.md`.

```yaml
---
paths:
  - "<glob pattern, quoted — YAML requires it for patterns starting with * or {>"
---
```

- Quote every glob pattern.
- Omit `paths:` entirely only for a rule meant to apply globally — this should be rare.
- One rule file per concern — a new convention with different trigger paths is a new rule, not an addition to an unrelated one.

---

## Step 3 — Writing new skills (`.claude/skills/<name>/SKILL.md`)

A skill's `name` + `description` are always in context; the body loads only when it triggers; anything under `scripts/`, `references/`, or `assets/` loads on demand.

- **`description` does double duty**: state what the skill does *and* when to use it, and lean slightly pushy — Claude tends to under-trigger skills, so spell out phrasings and contexts explicitly rather than trusting a vague description to be inferred.
- Keep the `SKILL.md` body under ~500 lines. If it's growing past that, split stable reference material into `references/*.md` and point to it from the body rather than inlining everything.
- Write instructions in the imperative, and explain *why* rather than issuing bare musts — same principle as docs and rules.
- Every new skill goes through the same Step 0 discipline: don't invent its instructions from a generic template — `references/skill.template.md` gives the *shape*, but the actual content still has to come from how the task is really done in this project, checking existing docs/rules/skills first so the new skill doesn't duplicate or contradict what already exists.

---

## Step 4 — Writing specs (`<topic>.spec.md`)

Unlike docs/rules/skills, this project's spec convention isn't something to discover per project — it's fixed, and fully defined in `references/spec.template.md` (naming, the living/no-history lifecycle, the 8 required sections, and how Claude should use it). Read that file in full before writing or updating a spec; nothing here or elsewhere restates it, so don't rely on this summary alone:

1. **Glob `**/*.spec.md` before writing one.** A spec names a cohesive slice (a component, a layer, a flow), and a slice only ever has one spec — if it already exists, update it in place rather than starting a new file.
2. **A spec is scoped to one cohesive slice**, not a single task or a whole subsystem — pick a grain that can have a real contract, not one that needs a new file every time work resumes on the same area.
3. **Don't skip sections to move faster.** The template is expensive to write by design: the cost of specifying up front is there to avoid the larger cost of discovering the real scope mid-implementation, or letting the document quietly stop matching reality.
4. **When the slice's reality changes, edit the existing spec** — don't leave it describing a past state, and don't create a separate log of what changed; the reasoning for a change belongs inline, in the section it affects.

---

## Step 5 — Before presenting the draft

- Re-read the finished artifact once as if you'd never seen the project: does every claim trace back to something actually read in Step 0, not something assumed?
- Check it against the length/format norms for its type (doc, rule, skill, spec) and confirm it matches its `references/*.template.md` skeleton.
- Confirm the language matches what's already used for that artifact kind in this project, not a default.
- If you touched an existing doc, confirm you didn't reintroduce a cross-reference between docs, or business/product language that was previously stripped.
- If Step 0 turned up a conflict between artifacts, or between an artifact and the code, lead with that when presenting the draft — don't bury it at the end.
