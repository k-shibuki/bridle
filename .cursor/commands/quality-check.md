# quality-check

## Purpose

Run linting, formatting checks, and R CMD check.

## When to use

- Before running the full test suite (typically before `regression-test`)
- Before merging/pushing

## Policy (rules)

Follow the quality policy here:

- `@.cursor/rules/quality-policy.mdc`

## Recommended Execution Order

Always format before linting. Running lint on unformatted code produces false positives from styler/lintr indentation conflicts (see `@.cursor/knowledge/lint--styler-lintr-conflict.md`).

```bash
# Step 1: Auto-format (fixes style issues)
make format

# Step 2: Verify formatting is clean (dry-run)
make format-check

# Step 3: Fast gate (schema validation + lint)
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
# Fast gate: schema validation + lint
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
make coverage-check     # Coverage gate (line coverage >= 80%)

# Differential (changed files only, faster iteration)
make changed-lint       # Lint only changed R files
```

Note: All `make` targets that invoke R run inside the Podman container.
The container must be running (`make container-up`). See `make doctor` to verify.

## Output (response format)

- **Issues found**: grouped by tool/code
- **Fixes applied**: summary + file list
- **Intentional exceptions**: list + reason

## Definition of Done

- `make pr-ready` passes (or at minimum `make check` passes with **0 errors, 0 warnings, 0 notes**)

## Troubleshooting

### format-lint loop (styler formats, lintr rejects, repeat)

**Symptom**: `make format` changes indentation, then `make lint` reports `indentation_linter` on the formatted code.

**Cause**: styler and lintr disagree on indentation for multi-line `if` conditions and `switch()` blocks.

**Fix**: Restructure the code to avoid the conflict. Extract multi-line conditions into named variables:

```r
# Before (triggers conflict):
if (is.null(x) ||
    length(x) == 0) {
  ...
}

# After (no conflict):
is_empty <- is.null(x) || length(x) == 0
if (is_empty) {
  ...
}
```

See `@.cursor/knowledge/lint--styler-lintr-conflict.md` for details.

### `object_usage_linter` false positives for S7 classes

**Symptom**: `lintr` reports "no visible global function definition for 'MyClass'" on S7 constructor calls.

**Cause**: `object_usage_linter` does not resolve S7 constructors defined in other files within the same package.

**Fix**: Add a targeted `# nolint` with the linter name and reason:

```r
result <- MyClass(...) # nolint: object_usage_linter. S7 class defined in R/my_class.R
```

### CI lint passes locally but fails remotely (or vice versa)

**Symptom**: `make ci-fast` passes locally but CI reports lint failures.

**Cause**: Local run may use cached format state. The CI environment starts clean.

**Fix**: Run the full sequence from scratch: `make format && make format-check && make ci-fast`.

## Coverage Commands

```bash
make coverage                 # Print coverage summary
make coverage-check           # Verify threshold (default 80%)
make coverage-check COVERAGE_THRESHOLD=70  # Override threshold (investigation only)
```

In CI, coverage results are uploaded to Codecov. See `codecov.yml` for configuration.

## Related rules

- `@.cursor/rules/quality-policy.mdc`
