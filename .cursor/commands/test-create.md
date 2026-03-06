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

- Do **not** reference archived documents in code comments.
- Use Given/When/Then comments for readability.
- Include **at least as many negative tests as positive tests**.
- Unit tests must **not** depend on external resources (network, remote services, model downloads).
  - Mock integration points (e.g., ellmer chat, ragnar search, HTTP clients) so tests are deterministic and non-hanging.

## Steps

1. Produce a test matrix (equivalence partitions + boundary cases) in Markdown.
2. Check `tests/testthat/helper-mocks.R` for existing mock factories. Reuse shared helpers where possible; add new shared patterns to the helper if they will be used across multiple test files.
3. Implement tests based on that matrix.
4. For any new parameter/field, add at least one **wiring/effect** test so the suite fails if the parameter is validated but not propagated/used:
   - Wiring: assert downstream call args / generated request includes the new parameter.
   - Effect: change the parameter value and assert behavior/output changes per requirements.
5. Add Given/When/Then comments.
6. Ensure exceptions include both type and message assertions when meaningful.

## Test matrix template

| Case ID | Input / Precondition | Perspective (Equivalence / Boundary) | Expected Result | Notes |
|---------|---------------------|--------------------------------------|----------------|-------|
| TC-N-01 | Valid input A       | Equivalence – normal                 | Processing succeeds | - |
| TC-A-01 | NULL                | Boundary – NULL                     | Validation error | - |

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
