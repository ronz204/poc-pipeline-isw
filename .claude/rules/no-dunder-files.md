---
paths:
  - "project/source/**"
  - "project/testing/**"
---

# Python Module Layout Conventions

This governs how files and packages are named and laid out under the source and test trees. It targets the project's Python 3.12 setup with a namespace-package build.

---

## No files named with double underscores

- Do not create `__init__.py` files. Python imports a directory as a package without one (namespace packages), and the build backend is configured for that layout, so an initializer adds nothing and clutters every folder. Editors, scaffolding tools, and `uv init` may create one without anyone noticing, so check for them after any scaffolding.
- Do not create any other file whose name contains double underscores either, `__main__.py` included, because the project keeps file names plain. The command-line entry point is a regular module that the installed command points at; running it as a module is done through that command or by guarding a `main` call inside the module itself.
- Names inside a file (`__name__`, dunder methods) are unaffected; this is about file and folder names.

## Test file names are unique

- Test modules have unique file names across the whole test tree, because without package initializers pytest imports each by its base name and two files with the same name collide.
- Shared fixtures live in a single conftest file, which is a plain pytest convention and not a dunder name.

---

## Non-goals

- Doesn't govern what goes inside modules or how packages are named, only the absence of dunder-named files and unique test names.
