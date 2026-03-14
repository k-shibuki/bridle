# test-create

## Reads
- `test-strategy.mdc` (test design policy, mock conventions, coverage targets)
- `test--perspectives-table.md` (table format, Issue Test Plan import, template)
- `test--mock-scope-constraint.md`, `test--mock-external-function.md`, `test--layered-mock-strategy.md` (mock patterns)
- `r--null-assignment-trap.md` (R language trap)
- `test--given-when-then.md` (GWT comment format)
- `test--helper-conventions.md` (helper files, shared mock factories)

## Sense

Review the implementation diff and the Issue's Test Plan section.

## Act

1. Import Issue Test Plan as baseline per `test--perspectives-table.md` § Step 0.
2. Produce a test perspectives table per `test--perspectives-table.md` § Table Format. Present before writing tests.
3. Check `tests/testthat/helper-mocks.R` for existing mock factories.
4. Implement tests based on the matrix. Include GWT comments, wiring/effect tests for new parameters, and exception type+message assertions.

## Output
- Test perspectives table (updated if scope changes)
- New/updated test files: list of paths
- Notes: gaps, flakiness risks, runtime concerns

## Guard
- `HS-NO-DISMISS`: every test failure is a defect
- Test design must follow `test-strategy.mdc`
