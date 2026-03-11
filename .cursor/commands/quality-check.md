# quality-check

## Purpose

Run linting, formatting checks, and R CMD check.

## When to use

- Before running the full test suite (typically before `test-regression`)
- Before merging/pushing

## Policy (rules)

Follow the quality policy here:

- `@.cursor/rules/quality-policy.mdc`

## Recommended Execution Order

Per `@.cursor/rules/quality-policy.mdc` § Execution Order: always format before linting. See the rule for rationale.

```bash
# Step 1: Auto-format (fixes style issues)
make format

# Step 2: Verify formatting is clean (dry-run)
make format-check

# Step 3: Fast gate (validate-schemas + renv-check + kb-validate + lint)
make ci-fast

# Step 4: Full CI (adds test + R CMD check)
make ci

# Step 5: Coverage gate (verify line coverage >= threshold)
make coverage-check

# Step 6: Knowledge base validation (if knowledge/ files changed)
make kb-validate
```

Skipping Step 1 and going directly to `make ci-fast` will cause lint failures on code that styler would have auto-fixed.

## Commands

Use `make` commands (run `make help` for all options):

```bash
# Fast gate: validate-schemas + renv-check + kb-validate + lint
make ci-fast

# Full CI: validate-schemas + lint + test + check
make ci

# Full pre-PR gate: validate-schemas + format-check + lint + test + check + document
make pr-ready

# Individual targets
make validate-schemas   # Validate YAML schemas
make lint               # Lint check (lintr)
make format             # Format (auto-fix with styler)
make format-check       # Format dry-run (exits non-zero if unformatted)
make check              # R CMD check (primary quality gate)
make coverage-check     # Coverage gate (threshold per test-strategy.mdc § Coverage Threshold Policy)

# Differential (changed files only, faster iteration)
make changed-lint       # Lint only changed R files
```

Note: All `make` targets that invoke R run inside the development container (see `@.cursor/rules/workflow-policy.mdc` § Container Prerequisite).

## Output (response format)

- **Issues found**: grouped by tool/code
- **Fixes applied**: summary + file list
- **Intentional exceptions**: list + reason

## Definition of Done

- `make pr-ready` passes (or at minimum `make check` passes with **0 errors, 0 warnings, 0 notes**)

## Verification Order

Which gate to run depends on what changed. All verifications are mandatory unless noted.

| Verification | Minimum gate | Executed during | Skippable? |
|---|---|---|---|
| `make validate-schemas` | Always | `quality-check` | No |
| `make ci-fast` | Always | `quality-check` | No |
| `make test` | When tests exist | `test-regression` | Only if no tests exist |
| `make check` | Before commit | `quality-check` | No |
| `make coverage-check` | When tests exist | `test-regression` | Only if no tests exist |
| `make document` | When roxygen2 changed | `quality-check` | Only if no roxygen2 changes |
| `gh pr checks` | Before merge | `pr-create` (Step 5) | No |
| `make doctor` | Always (includes renv sync) | `quality-check` | No |
| `roxygen2::roxygenise()` | After `git rebase` adding new R files | `quality-check` | No |

When no R code changed (Makefile, docs, CI only) but schema-related files were modified, run `make validate-schemas`. When neither R code nor schemas changed, local verification may be skipped.

## Troubleshooting

- **format-lint loop** (styler formats, lintr rejects): See `@.cursor/knowledge/lint--styler-lintr-conflict.md`
- **`object_usage_linter` false positives for S7**: See `@.cursor/knowledge/lint--s7-cross-file-reference.md`
- **CI lint passes locally but fails remotely**: See `@.cursor/knowledge/lint--ci-local-divergence.md`

## Coverage Commands

```bash
make coverage                 # Print coverage summary
make coverage-check           # Verify threshold (see test-strategy.mdc § Coverage Threshold Policy)
make coverage-check COVERAGE_THRESHOLD=70  # Override threshold (investigation only)
```

In CI, coverage runs on main push (`R-CMD-check.yaml`) with auto-Issue on threshold failure.

### Schema validation errors

| Error | Fix |
|---|---|
| YAML parse error | Fix YAML syntax (indentation, quoting) |
| Missing top-level key | Add required key per schema spec |
| Unrecognised schema type | Rename file to match `*.schema.yaml` pattern or add rule |

Schema validation runs via `make validate-schemas` (also part of `make ci-fast`). Currently checks YAML syntax, top-level structure, and filename convention. Future S7 validator integration will add cross-reference and reachability checks.

## Related rules

- `@.cursor/rules/quality-policy.mdc`
