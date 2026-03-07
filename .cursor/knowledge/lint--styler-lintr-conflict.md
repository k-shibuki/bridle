---
trigger: styler lintr conflict, indentation conflict, format lint disagree
---
# styler / lintr Indentation Conflicts

`styler` and `lintr`'s `indentation_linter` can disagree on indentation for certain constructs. When `make format` produces code that `make lint` rejects, the root cause is usually one of:

| Construct | Symptom | Resolution |
|-----------|---------|------------|
| Multi-line `if` condition | `styler` wraps the condition; `lintr` reports wrong indentation on the body | Extract the condition into a named variable, then use a single-line `if` |
| `switch()` with long cases | `styler` reformats case alignment; `lintr` disagrees | Build the value programmatically or use `match.arg()` instead |
| Pipe chains in arguments | Indentation of closing `)` after pipe | Break into intermediate variables |

**Key point**: The first fix to try is always **restructuring the code** (extract variable, split expression), not `# nolint`. Code restructuring resolves the conflict for both tools.

**Correct execution order**: Always run `make format` **before** `make ci-fast`. Running lint without formatting first produces false positives from these conflicts.
