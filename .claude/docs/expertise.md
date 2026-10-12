# Expertise

How the non-trivial mechanisms this pipeline relies on actually behave. Where and why each is used is not covered here.

---

## Glossary

| Term | Meaning |
|---|---|
| ETL | Extract, transform, load: data is validated and transformed before it reaches the destination. ELT loads raw data first and transforms inside the destination. |
| DataOps | DevOps practices applied to data pipelines: version control, automated tests, CI, reproducible environments, observability, and data quality as part of the process. |
| Dead-letter / quarantine | A side store for records that could not be processed, kept with the reason so they can be reviewed or reprocessed. |
| Circuit breaker | A guard that stops a process when failures exceed a limit instead of continuing with bad input. |
| Namespace package | A package directory with no `__init__.py`; Python imports it as a package anyway (PEP 420). |

## Idempotency through `ON CONFLICT DO NOTHING`

Inserting with `ON CONFLICT (key) DO NOTHING` skips a row whose key already exists instead of raising an error, and the statement's affected-row count is 1 when the row was inserted and 0 when it was skipped. That count is what lets a loader tell new rows from existing ones exactly. The guarantee is about the key only: it never compares the other columns, so a row with an existing key and different values is silently skipped. Calling the load twice with the same file therefore leaves the table unchanged, but it cannot detect that the second file disagreed with the first.

## Transactions and what stays committed

In autocommit mode every statement commits on its own; inside an explicit transaction block nothing is visible to other sessions until commit, and an exception rolls the whole block back. The pipeline deliberately mixes the two: the run row and the quarantine rows are autocommitted so they survive a failure, while all sale inserts and the reconciliation queries share one transaction so a failed check removes every insert of that run. Constraint violations raised by the database abort the entire transaction, which is why range checks happen in validation: a single out-of-range row that reached the insert would fail the whole batch rather than being quarantined.

## Exact money arithmetic

Binary floating point cannot represent most decimal fractions, so `3 × 6.10` accumulates rounding noise. Python's `Decimal` and PostgreSQL's `NUMERIC(p, s)` store decimal digits exactly. The total of a sale is computed with `Decimal` and re-checked by the database as `quantity × unit_price`; equality only holds because both sides use exact arithmetic. Precision matters: `NUMERIC(14,2)` holds at most twelve integer digits, so the quantity and price bounds are chosen so their product always fits.

## Reading CSV as text

Type inference in CSV readers turns `007` into `7`, empty strings into NA, and mixed columns into floats, which hides defects before validation sees them. Reading every column as a string and keeping empty strings as empty values means validation judges the original text. Two practical details: a UTF-8 byte-order mark written by spreadsheet programs would otherwise attach to the first header name, and a reader that skips blank lines shifts the record numbers reported for later rows.

## Declared validation with lazy evaluation

A schema of named checks separates what is valid from how failures are reported. Evaluating lazily collects every failing check for every row instead of stopping at the first, which is what allows one row to carry several reason codes. A check that is a boolean test over a whole column returns one result per row; the check's name, not its implementation, becomes the reason code. Format checks must tolerate empty values, otherwise an empty field would be reported both as missing and as malformed.

## Property-based testing of the accounting invariant

A property test generates many varied inputs and asserts a statement that must hold for all of them, then shrinks any failure to a minimal example. The statement here is accounting: for any table of input rows, the valid rows plus the rejected rows equal the input, no rejected row appears in the valid output, and valid identifiers are unique. It complements example-based tests by covering inputs nobody thought to write down.

## Spreadsheet formula injection

A CSV cell that begins with `=`, `+`, `-`, `@`, tab, or carriage return can be executed as a formula when the file is opened in a spreadsheet program. Because the quarantine file contains raw untrusted values and is meant to be opened by people, such cells are prefixed with an apostrophe. The database copy keeps the original value.

## Namespace packages and the build backend

With no `__init__.py`, Python still imports a directory as a package, and package data files next to modules remain reachable through the standard resource API. A build backend must be told to accept such a layout and where the module root is; otherwise it expects a conventional source layout and an initializer file.

---

## Non-goals

- Not a tutorial on the libraries in the stack; only behavior this pipeline depends on.
