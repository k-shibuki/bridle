# R Lint & Format Patterns

Recurring lint/format issues in the bridle codebase and their recommended resolutions.

**Policy**: See `@.cursor/rules/quality-check.mdc` for enforceable requirements.

---

## styler / lintr Indentation Conflicts

`styler` and `lintr`'s `indentation_linter` can disagree on indentation for certain constructs. When `make format` produces code that `make lint` rejects, the root cause is usually one of:

| Construct | Symptom | Resolution |
|-----------|---------|------------|
| Multi-line `if` condition | `styler` wraps the condition; `lintr` reports wrong indentation on the body | Extract the condition into a named variable, then use a single-line `if` |
| `switch()` with long cases | `styler` reformats case alignment; `lintr` disagrees | Build the value programmatically or use `match.arg()` instead |
| Pipe chains in arguments | Indentation of closing `)` after pipe | Break into intermediate variables |

**Key point**: The first fix to try is always **restructuring the code** (extract variable, split expression), not `# nolint`. Code restructuring resolves the conflict for both tools.

**Correct execution order**: Always run `make format` **before** `make ci-fast`. Running lint without formatting first produces false positives from these conflicts.

---

## `object_usage_linter` and S7 Cross-File References

`lintr`'s `object_usage_linter` does not resolve S7 class constructors defined in other files within the same package. References like `ParameterInfo(...)` or `ScanResult(...)` in a file that does not define them will be flagged as "no visible global function definition."

**Resolution**: Apply `# nolint: object_usage_linter.` at the specific line with a reason comment. This is a known lintr limitation with S7, not a code defect.

```r
result <- ScanResult(...) # nolint: object_usage_linter. S7 class defined in R/scan_result.R
```

---

## `object_length_linter` and Naming

R's default `object_length_linter` limit is 30 characters. Descriptive function names in a layered architecture easily exceed this.

**Strategies**:
- Prefer shorter, domain-specific names: `extract_rd_valid_values` over `extract_valid_values_from_descriptions`
- Use abbreviations established in the codebase: `rd` for Rd documentation, `params` for parameters
- If renaming is not feasible, use `# nolint: object_length_linter.` with reason

---

## Justified `# nolint` Usage

The following are **accepted justifications** (always include the reason after the linter name):

| Linter | Justification | Example |
|--------|---------------|---------|
| `object_usage_linter` | S7 constructor defined in another file within the same package | `# nolint: object_usage_linter. S7 class in R/foo.R` |
| `object_usage_linter` | `testthat::local_mocked_bindings` parameter names matching mocked functions | `# nolint: object_usage_linter. mock binding` |
| `object_name_linter` | Mock parameter names matching external package conventions (e.g., `event.e`) | `# nolint: object_name_linter. matches survival package API` |
| `line_length_linter` | Long URL or error message that cannot be meaningfully split | `# nolint: line_length_linter. error message` |

**NOT accepted**:
- `# nolint` without specifying the linter name
- `# nolint` without a reason comment
- Blanket `# nolint` to silence multiple unrelated warnings on one line
- Using `# nolint` to avoid fixing actual code quality issues

---

## Suggests Package Dynamic Loading Pattern

When a package is in `Suggests` (not `Imports`), calling `pkg::fn()` directly triggers an R CMD check warning ("'::' or ':::' import not declared from").

**Pattern**: Use `utils::getFromNamespace()` for dynamic access:

```r
bridle_chat <- function(...) {
  if (!requireNamespace("ellmer", quietly = TRUE)) {
    stop("Package 'ellmer' is required. Install with install.packages('ellmer').")
  }
  chat_fn <- utils::getFromNamespace("chat", "ellmer")
  chat_fn(...)
}
```

This keeps the dependency optional while passing R CMD check cleanly.
