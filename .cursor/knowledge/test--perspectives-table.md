---
trigger: test perspectives table, test matrix format, issue test plan import, test case columns, GWT test template
---
# Test Perspectives Table

Format specification for the test perspectives table used during test design.
This atom defines the table structure, Issue Test Plan import process, and
the template. Policy for test design is in `test-strategy.mdc`.

## Step 0: Import Issue Test Plan as Baseline

The Issue's Test Plan section serves as the **initial test matrix** — concrete,
self-contained test cases created at planning time. Build on that foundation:

1. **Start from the Issue**: Import the test cases from the Issue's Test Plan
   as the baseline rows of the test perspectives table.
2. **Expand systematically**: Add equivalence partitions, boundary values, and
   implementation-specific cases not apparent at Issue creation time.
3. **Maintain traceability**: Each Issue Test Plan scenario should map to at
   least one implemented test. If a scenario is dropped or merged, note the
   reason in the table.

## Table Format

Present a Markdown test perspectives table **before** writing any test code.

Required columns:

| Column | Description |
|--------|-------------|
| Case ID | `TC-N-##` (normal), `TC-A-##` (abnormal), `TC-B-##` (boundary) |
| Input / Precondition | Concrete values — not "valid input" |
| Perspective | Equivalence / Boundary classification |
| Expected Result | Specific outcome — not "succeeds" |
| Snapshot? | Whether `expect_snapshot` is used |
| Notes | Boundary justification, related acceptance criteria |

Rows must cover:

- Normal cases (main scenarios)
- Abnormal cases (validation errors, exception paths)
- Boundary values: 0 / min / max / ±1 / empty / NULL (omit only when
  meaningless per specification, with reason in Notes)

## Template

```markdown
| Case ID | Input / Precondition | Perspective (Equivalence / Boundary) | Expected Result | Snapshot? | Notes |
|---------|---------------------|--------------------------------------|----------------|-----------|-------|
| TC-N-01 | Valid input A       | Equivalence – normal                 | Processing succeeds | - | - |
| TC-A-01 | NULL                | Boundary – NULL                     | Validation error | Yes | Complex multi-line error |
```

## When the Table is Optional

For minor modifications to existing tests (message adjustments, minor expected
value changes) that don't add new branches or constraints, creating/updating
the table is optional.

## Related

- `test-strategy.mdc` — test design policy (perspectives, coverage, mocks)
- `test--given-when-then.md` — GWT comment format for test cases
- `test--helper-conventions.md` — helper files and mock factories
