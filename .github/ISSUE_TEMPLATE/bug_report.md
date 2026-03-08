---
name: Bug Report
about: Report a bug or unexpected behavior
title: "fix: "
labels: fix
---

## Description

<!-- A clear description of the bug. -->

## Steps to Reproduce

1.
2.
3.

## Expected Behavior

<!-- What should happen? -->

## Actual Behavior

<!-- What actually happens? Include error messages or tracebacks. -->

## Environment

<!-- Paste output of `make doctor-json` or `make doctor` -->

```
make doctor output here
```

## Related ADR / Schema

<!-- If related to a specific design decision or schema -->

- ADR:
- Schema:

## Impact / Workaround

- Impact: <!-- Who/what is affected? How severe? -->
- Workaround: <!-- Is there a temporary workaround? -->

## Acceptance Criteria (Definition of Done)

<!-- When is this bug considered fixed? -->

- [ ] Bug no longer reproducible with steps above
- [ ] Regression test added
- [ ]

## Regression Test Plan

<!--
Include CONCRETE test cases with specific input values and expected outputs.
The Issue should be self-contained — a reader can verify the fix without other docs.

Requirements:
- Original bug scenario with exact reproduction inputs and the now-correct expected result
- At least 1 edge case near the bug boundary
- At least 1 error/validation case if the fix changes error handling

Anti-patterns (DO NOT use):
- "valid input" / "invalid input" without specifics
- "succeeds" / "fails" without describing the outcome
-->

| Scenario | Input / Precondition | Expected Result | Notes |
|----------|---------------------|-----------------|-------|
| Original bug reproduced | <!-- exact inputs from Steps to Reproduce --> | <!-- correct behavior after fix --> | Regression guard |
| <!-- e.g., Similar input that was NOT broken --> | <!-- concrete values --> | <!-- still works correctly --> | Ensures no side effects |
| <!-- e.g., Edge case near bug boundary --> | <!-- concrete values --> | <!-- expected behavior --> | Boundary |

## Priority / Affected Area

- Priority: <!-- high / medium / low -->
- Affected area: <!-- e.g., R/, docs/schemas/, tests/ -->
