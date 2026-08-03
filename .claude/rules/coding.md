# Code Quality Conventions

Language-agnostic guidance for writing clean, well-structured code — coupling, cohesion, SOLID, and common smells apply the same regardless of the file's language or the layer it sits in (application code, data access, stored procedures, UI). The goal is to keep these in mind *while writing*, not just recall them when reviewing after the fact.

Whatever module boundaries the current codebase already establishes — path aliases, a `features/`-style directory split, a layered folder structure — are the intended seams. A relative import chain walking several directories up and back down, past a boundary that already has a shorter, established path to it, is a coupling smell on sight, independent of anything else about the code.

---

## 1. Coupling smells — the headline priority

| Smell | What it looks like | Why it matters |
|---|---|---|
| **Shotgun surgery** | One logical change requires touching many unrelated files — the same concept (a status enum, a field name, a validation rule) duplicated or referenced across N places with no single owner. | The cost of every future change to that concept scales with N, and it's easy to update N-1 of N and ship a bug. |
| **Feature envy** | A function in module A calls mostly module B's getters/fields, barely touching A's own data. | The logic is living in the wrong place — it should be a method/function on or near B, or B should be passed in already-shaped instead of raw. |
| **Inappropriate intimacy** | Two modules reach into each other's internals — accessing another module's private state, or two files that only work correctly because of undocumented assumptions about each other's implementation. | Neither module can change independently; testing one requires standing up the other. |
| **God object / god module** | One file or class knows about and orchestrates a large portion of the system — many unrelated things import from it, and it imports many unrelated things. | Every unrelated change has a chance of touching this file, and this file has a chance of breaking every unrelated feature. |
| **Temporal coupling** | Correctness depends on call order that nothing in the type system or API shape enforces (e.g. "must call `init()` before `use()`," with `use()` silently misbehaving otherwise). | The mistake is invisible until runtime, often only under a specific ordering that's rare in dev and common in prod. |
| **Circular dependencies** | Module A imports from B, and B imports from A — directly, or through a longer chain. | Breaks independent reasoning and testing; in a bundler, can produce partially-initialized-module bugs that only show up depending on import order. |
| **Sequential coupling via shared mutable state** | Two functions coordinate only by reading/writing a shared external variable rather than explicit parameters and return values. | The dependency between them is invisible at each call site — a reader has to trace the mutable state to understand the actual contract. |

## 2. Cohesion smells

| Smell | What it looks like | Why it matters |
|---|---|---|
| **Divergent change** | One file changes for many unrelated reasons over time (a change to auth logic, a change to validation, a change to logging — all touching the same file). | This is SRP violation viewed from the maintenance-frequency angle — the file is where unrelated concerns collide. |
| **Large file/class mixing concerns** | Parsing, I/O, and business rules all in one file or unit with no internal separation. | Can't test the business rule without the I/O; can't change the I/O without risking the business rule. |
| **Data clumps** | The same group of parameters/fields (e.g. `street, city, zip`) travels together across many function signatures without being modeled as its own type. | Signal that a value object/type is missing — passing the group loose invites one field being forgotten or misordered at a call site. |
| **Primitive obsession** | A raw `string`/`number` standing in for a concept that deserves its own type (an identifier, an amount, a status that's really a closed set of states). | The type system can't catch a mixed-up argument order or an invalid value; validation logic ends up duplicated at every use site instead of centralized in the type. |

## 3. SOLID

- **SRP**: does this unit have more than one reason to change? Two features that happen to touch the same file for unrelated reasons is the tell.
- **OCP**: does adding a new case require editing existing, already-stable branching logic (a long `IF`/`CASE`/`switch` that keeps growing), instead of adding a new, isolated implementation? Only worth flagging where new cases are actually expected to keep arriving — not every branch needs to be open for extension.
- **LSP**: does an implementation throw, return `null`/`NULL` unexpectedly, or otherwise narrow behavior in a way the base type's or base procedure's contract doesn't promise? A subtype or overload that surprises callers who only know the general contract is an LSP violation even if it type-checks.
- **ISP**: is a caller forced to depend on, implement, or import a much wider interface than it actually uses? A consumer that only needs one field of a type shouldn't have to accept (and therefore couple to) the whole thing — same idea applies to a function/query that returns 15 columns when the caller reads 2.
- **DIP**: does high-level logic import and directly instantiate a low-level/concrete dependency where there's an actual, present reason to invert it (testability, a real second implementation, a swap already planned)? DIP applied where there's no real reason to invert is itself a smell — indirection with no payoff.

## 4. Classic smells

- **Long method** — if it doesn't fit on one screen without scrolling, it's a candidate; the real test is whether it does one identifiable thing or several.
- **Long parameter list** (roughly >4-5) — often a sign of a data clump; consider a single options object or a composite type instead.
- **Deeply nested conditionals** (more than 2-3 levels) — prefer guard clauses / early returns / early validation failures over a pyramid of nested branches.
- **Boolean flag parameters** (`doThing(true)`) — unclear at the call site what `true` means without checking the signature; prefer a named options object, a string literal union, or splitting into two functions.
- **Magic numbers/strings** — an unexplained literal standing in for a constant that should be named.
- **Dead code / commented-out code** — if it's not running, it shouldn't be in the file; version control is the place for "what used to be here."
- **Speculative generality** — unused parameters, hooks, or abstraction layers built for a future need that isn't real yet. Three similar lines are better than a premature abstraction; don't design for hypothetical requirements.
- **Anemic domain model** — data-only types paired with a separate "service" that contains all the logic operating on them, when the logic naturally belongs on the type itself.
- **Error swallowing** — a `catch` block that discards the error, or an exception handler that suppresses without re-raising or logging, with no signal to the caller about what failed.

## Design patterns

Reach for a well-known pattern when the problem it solves is actually present — and just as importantly, notice when one is being applied for its own sake: an abstraction with a single implementation and no real second one planned, a wrapper around trivial construction logic, or indirection that doesn't buy testability or a genuine swap. Pattern misuse is as real a smell as a missing pattern — treat an unjustified abstraction the same as any other premature one.

---

## Non-goals

This rule governs the structure and quality of code that's already been decided to write. It isn't a checklist of business or domain requirements a given piece of code must satisfy — those live wherever this project's own specs and requirements are documented.
