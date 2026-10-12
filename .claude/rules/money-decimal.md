---
paths:
  - "project/source/**/*.py"
  - "project/testing/**/*.py"
---

# Monetary Value Conventions

This governs how prices and totals are represented in Python code and in tests that assert on them. The database side is `NUMERIC`; this rule is about the Python side matching it.

---

## Exact decimals only

- Monetary values (unit price, total, anything derived from them) are `Decimal` from parsing to persistence, never `float`, because binary floating point cannot represent most decimal fractions and `3 × 6.10` would accumulate rounding noise that the database `CHECK` on the total would then reject or, worse, accept inconsistently.
- Build a `Decimal` from the original text, never from a float. `Decimal(0.1)` carries the float's error; `Decimal("0.1")` does not.
- Quantize to two decimal places explicitly when normalizing a price, because the stored scale is fixed and implicit rounding would hide a malformed input.
- Do not pass money through a pandas numeric column conversion on its way to the database, because that converts to float; keep it as a column of `Decimal` objects or convert at the boundary.
- Tests assert money with `Decimal` literals, never float literals, because comparing against a float would pass or fail depending on representation error.

---

## Non-goals

- Doesn't apply to counts (quantity, row totals) or other non-monetary numbers.
