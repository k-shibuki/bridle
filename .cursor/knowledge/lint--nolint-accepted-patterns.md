---
trigger: nolint justification, nolint accepted, nolint prohibited, nolint pattern, object_length_linter, object_usage_linter, object_name_linter, line_length_linter, 30 character limit, long function name, naming length
---
# Justified `# nolint` Usage

**Before using `# nolint`**: Follow `quality-policy.mdc` § nolint Checkpoint — Priority 1 (restructuring) and Priority 2 (co-location) must be exhausted first. For test code `object_usage_linter`, see `test--mock-scope-constraint.md` to determine which helpers can be co-located.

The following are **accepted justifications** (always include the reason after the linter name):

| Linter | Justification | Example |
|--------|---------------|---------|
| `object_usage_linter` | S7 constructor defined in another file within the same package | `# nolint: object_usage_linter. S7 class in R/foo.R` |
| `object_usage_linter` | `testthat::local_mocked_bindings` parameter names matching mocked functions | `# nolint: object_usage_linter. mock binding` |
| `object_name_linter` | Mock parameter names matching external package conventions (e.g., `event.e`) | `# nolint: object_name_linter. matches survival package API` |
| `line_length_linter` | Long URL or error message that cannot be meaningfully split | `# nolint: line_length_linter. error message` |

**NOT accepted**: See `quality-policy.mdc` § Prohibited forms for the authoritative list of rejected nolint patterns.

## `object_length_linter` and Naming

R's default `object_length_linter` limit is 30 characters. Descriptive function names in a layered architecture easily exceed this.

**Strategies** (try before resorting to nolint):

- Prefer shorter, domain-specific names: `extract_rd_valid_values` over `extract_valid_values_from_descriptions`
- Use abbreviations established in the codebase: `rd` for Rd documentation, `params` for parameters
- If renaming is not feasible, use `# nolint: object_length_linter.` with reason
