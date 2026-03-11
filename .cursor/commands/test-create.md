# test-create

## Purpose

Design and implement tests for the implemented change.

## When to use

- After implementing a task (typically after `implement`)
- Any time coverage is missing for a change you introduced

## Inputs (attach as `@...`)

- `@docs/adr/` (recommended)
- Relevant source files (`@R/...`) and existing tests (`@tests/testthat/...`) (recommended)

## Constraints

Follow `@.cursor/rules/test-strategy.mdc` for test design policy (perspectives table, negative test ratios, mock conventions, external resource isolation). Key operational constraints for this command:

- Use Given/When/Then comments for readability
- Mock integration points so tests are deterministic and non-hanging

## Steps

### Step 0: Import Issue Test Plan as baseline

The Issue's Test Plan section serves as the **initial test matrix** — concrete, self-contained test cases created at planning time. This step builds on that foundation:

1. **Start from the Issue**: Import the test cases from the Issue's Test Plan as the baseline rows of the test perspectives table.
2. **Expand systematically**: Add equivalence partitions, boundary values, and implementation-specific cases that weren't apparent at Issue creation time.
3. **Maintain traceability**: Each Issue Test Plan scenario should map to at least one implemented test. If an Issue scenario is dropped or merged, note the reason in the table.

The Issue Test Plan is intentionally detailed (concrete inputs, expected outputs) so that:
- The Issue is **self-contained** — anyone can understand what to test without consulting other documents
- Implementation and review can proceed independently
- Test coverage gaps are visible early, before code is written

### Step 1: Produce a test perspectives table

Before starting any test work, present a Markdown "test perspectives table."

1. The table must include at least these columns: `Case ID`, `Input / Precondition`, `Perspective (Equivalence / Boundary)`, `Expected Result`, `Notes`.
2. Rows should cover normal, abnormal, and boundary value cases. For boundary values, include at minimum `0 / min / max / ±1 / empty / NULL`.
   Boundary value candidates (0 / min / max / ±1 / empty / NULL) that are meaningless per specification may be omitted with reason stated in `Notes`.
3. If perspective gaps are discovered later, update the table after self-review and add necessary cases.
4. For minor modifications to existing tests (message adjustments, minor expected value changes) that don't add new branches or constraints, creating/updating the test perspectives table is optional.

### Step 2: Implement tests

1. Check `tests/testthat/helper-mocks.R` for existing mock factories. Reuse shared helpers where possible; add new shared patterns to the helper if they will be used across multiple test files.
2. Implement tests based on the matrix.
3. For any new parameter/field, add at least one **wiring/effect** test so the suite fails if the parameter is validated but not propagated/used:
   - Wiring: assert downstream call args / generated request includes the new parameter.
   - Effect: change the parameter value and assert behavior/output changes per requirements.
4. Add Given/When/Then comments (see `@.cursor/knowledge/test--given-when-then.md` for the template).
5. Ensure exceptions include both type and message assertions when meaningful.

## Test matrix template

| Case ID | Input / Precondition | Perspective (Equivalence / Boundary) | Expected Result | Snapshot? | Notes |
|---------|---------------------|--------------------------------------|----------------|-----------|-------|
| TC-N-01 | Valid input A       | Equivalence – normal                 | Processing succeeds | - | - |
| TC-A-01 | NULL                | Boundary – NULL                     | Validation error | Yes | Complex multi-line error |

## Running tests (recommended)

Use `make` commands (run `make help` for all options).

```bash
# Run all tests
make test

# Run specific test files or filter (via container shell)
make container-shell
# then inside the container:
Rscript -e "devtools::test(filter = 'decision_graph')"

# Run with coverage
make coverage
```

## Output (response format)

- **Test matrix**: table (updated if scope changes)
- **New/updated test files**: list of paths
- **Notes**: gaps, flakiness risks, runtime concerns

## Related rules

- `@.cursor/rules/test-strategy.mdc`
