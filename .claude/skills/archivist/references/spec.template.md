<!--
Template AND methodology for <topic>.spec.md — this file is self-contained on
purpose: it is the only place Swampert's spec-driven-development convention
lives, so read it in full before writing or updating a spec, don't assume the
shape from memory or from a similar file in another project.

WHAT A SPEC IS HERE
A `<topic>.spec.md` names one cohesive slice of the system (a component, a
layer, a flow — e.g. `drizzle-db.spec.md`, `dashboard.spec.md`), not a batch
of tasks for a given day. There is no fixed location and no single canonical
file — Glob `**/*.spec.md` before assuming one doesn't already exist for the
topic at hand.

LIVING, NOT ONE-SHOT
A spec is not a disposable pre-implementation plan. It is never closed,
deleted, or replaced once the first implementation lands — it keeps being
edited in place every time that slice's reality changes (a new case, a
changed validation, a discovered edge case). A spec always describes the
*current* contract and state of that slice, never a snapshot of what was
once planned.

NO history/ FOLDER
This is deliberate: if the reason for a change matters, it gets written into
the relevant section of the spec itself at the moment of editing — there is
no separate append-only decision log and no per-slice folder structure.
Simpler is correct at this project's size; don't reintroduce one.

HOW CLAUDE SHOULD USE THIS
- Before implementing anything non-trivial, check whether a `*.spec.md`
  already exists for that topic. If it does, edit it in place to reflect the
  new reality — never create a second spec for the same slice, and never
  reinterpret its scope without updating the document itself.
- If the work is non-trivial and no spec exists yet, propose writing one
  using the 8 sections below before touching code.
- Don't skip sections to move faster. The template is expensive to write on
  purpose — the cost of specifying up front is there to avoid the larger
  cost of discovering the real scope mid-implementation.
- This coexists with — doesn't replace — Claude Code's own Plan mode. Use
  Plan mode for exploratory work where it's still unclear what will be
  built; use this template once a slice is defined enough to specify in
  writing.

Fill every section below; delete this guidance comment before presenting the
draft.
-->

# <Topic> — Spec

## Objective

<!-- One sentence: the observable result/contract, not the activity. "X validates Y and fails with Z when W", not "work on X". If the objective can be written as a list of sub-tasks, it's not an objective yet — it's a plan disguised as one. -->

## Scope

<!-- What's in today. Then, explicitly, what's out — naming what's deferred and why it's safe to defer is what keeps the spec from being silently assumed to cover something it doesn't. -->

## Technical context

<!-- What already exists that this slice touches or depends on: concrete files, prior decisions, related docs. Enough that someone with no memory of this conversation could act on the spec without re-exploring the project from scratch. -->

## Implementation

<!-- Concrete steps, files to create/touch, in order. Not full pseudocode, but specific enough that the sequence of decisions is already made before the editor opens. -->

## Config / secrets

<!-- New or affected environment variables / credentials, and where their expected value comes from. Omit this section entirely if genuinely not applicable — don't leave it as a stub. -->

## Acceptance criteria

<!-- Binary checklist (`- [ ]`). Each item must be markable yes/no without judgment. If an item needs interpretation to know whether it passed, it isn't written precisely enough yet. Because the spec is living, these get checked and unchecked as the slice's real state changes — they are not frozen at authoring time. -->

## How to test

<!-- The exact command or manual flow to verify — not "test the feature", but the exact call/request, with what input, and what the expected output or error is. -->

## Risks / edge cases

<!-- What could fail silently if not thought through now: implicit decisions worth making explicit, edge-case inputs, interactions with existing behavior, performance/volume concerns. -->
