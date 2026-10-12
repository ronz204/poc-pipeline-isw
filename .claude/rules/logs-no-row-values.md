---
paths:
  - "project/source/**/*.py"
---

# Logging Content Conventions

This governs what log events and run summaries may contain. It applies to every structured log call and to every report or console summary the pipeline produces.

---

## Counts and codes, never row values

- Log events and summaries carry counts, rejection reason codes, statuses, durations, and the run identifier, never the values of a source row, because source rows may contain personal data and logs are copied into CI artifacts and job summaries that outlive the run.
- The only places raw row values may live are the database table that holds rejected records and the per-run quarantine CSV, because those are the controlled, reviewable stores for that data.
- An error message built from an exception must not echo a row's content. If a failure concerns a specific row, identify it by record number and reason code instead.
- Event names are stable, snake_case identifiers and extra context is passed as separate fields, not interpolated into the message, because dashboards and greps key on the event name.

---

## Non-goals

- Doesn't restrict logging file names, directory paths, or column names, which carry no row data.
