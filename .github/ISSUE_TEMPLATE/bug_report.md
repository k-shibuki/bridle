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

<!-- When is this bug considered fixed? Use plain bullets (- item), not checkboxes. -->

- Bug no longer reproducible with steps above
- Regression test added
-

## Regression Test Plan

<!-- Concrete test cases: original bug scenario + edge cases + error cases.
     Use specific inputs and expected outputs, not vague placeholders.
     Full guidelines: .cursor/commands/issue-create.md § Test Plan Guidelines -->

| Scenario | Input / Precondition | Expected Result | Notes |
|----------|---------------------|-----------------|-------|
| Original bug reproduced | <!-- exact inputs from Steps to Reproduce --> | <!-- correct behavior after fix --> | Regression guard |
| <!-- e.g., Similar input that was NOT broken --> | <!-- concrete values --> | <!-- still works correctly --> | Ensures no side effects |
| <!-- e.g., Edge case near bug boundary --> | <!-- concrete values --> | <!-- expected behavior --> | Boundary |

## Priority / Affected Area

- Priority: <!-- high / medium / low -->
- Affected area: <!-- e.g., R/, docs/schemas/, tests/ -->
