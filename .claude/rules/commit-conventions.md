# Commit Message Conventions

This governs every git commit message written in this repository, by a person or by Claude. It applies globally, so it carries no `paths:` scope. Pull request titles are out of scope.

---

## Format

- The subject follows Conventional Commits: `type(scope): subject`. A scope is optional but preferred, because it makes `git log --oneline` scannable by area.
- Allowed types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`. A fixed vocabulary keeps history greppable and lets tooling derive changelogs.
- The whole subject line, type and scope included, is between 40 and 50 characters. Under 40 usually means the message says too little to be useful; over 50 gets truncated in common git UIs.
- The subject is in the imperative mood ("add", not "added" or "adds"), lowercase after the colon, with no trailing period. The imperative reads as what applying the commit does.
- A body is optional. When used, separate it from the subject with a blank line and explain why the change was made, not what the diff already shows.

## Language

- Commit messages are written in English, whatever language the team speaks day to day, because history is read by tooling and future contributors who may not share that language.

## Atomic and cohesive commits

- One logical change per commit, because small commits can be reverted or bisected without collateral damage. If the subject needs "and" to describe the change, it is probably two commits.
- Group files by concern, not by when they were touched: knowledge-base files, project configuration, source, and tests each go in their own commits, because a mixed commit cannot be reverted without losing unrelated work.
- Stage explicitly by path (or hunk when one file carries two concerns); never `git add -A` or `git add .`, because they sweep unrelated or sensitive files into the commit. Review the staged diff before committing.
- Every commit leaves the repository in a working state: no half-written file that only makes sense with the next commit, because bisecting lands on arbitrary commits.
- Never commit secrets or real environment files; only the `.sample` variants are versioned.
- Keep refactors, renames, and behavior changes in separate commits, because a diff that does both hides the behavior change.
- Choose the type by what the change is: `docs` for knowledge-base, README, and roadmap content; `chore` for repo housekeeping and scaffolding; `build` for packaging and dependency configuration; `ci` for workflow changes; `feat`, `fix`, `refactor`, `test` for source changes.

---

## Non-goals

- Doesn't dictate branch names or pull request titles.
