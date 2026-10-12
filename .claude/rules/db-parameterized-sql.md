---
paths:
  - "project/source/**/*.py"
---

# Parameterized SQL Conventions

This governs every SQL statement the pipeline's code sends to PostgreSQL. It targets the psycopg driver. Schema definition files are out of scope: they contain no runtime data.

---

## Values travel as parameters, never as text

- Every value that originates outside the code (CSV cells, file names, run identifiers, settings) is passed as a bound parameter, never interpolated, concatenated, or formatted into the SQL string, because the CSV is untrusted input and a crafted cell would otherwise become executable SQL.
- No linter in this project's configuration catches string-built SQL, so the review of any changed statement has to check this by eye.
- Identifiers (table or column names) are fixed in code and never derived from input. When an identifier genuinely has to vary, use the driver's identifier-composition facility, never string formatting, because identifiers cannot be bound as parameters.

## Batches stay parameterized too

- Multi-row inserts pass a sequence of parameter tuples to the driver; they do not build a long statement with embedded values, because that reintroduces the injection path and defeats statement reuse.

---

## Non-goals

- Doesn't cover how rows are batched or the transaction boundaries; those are the pipeline's own contract.
