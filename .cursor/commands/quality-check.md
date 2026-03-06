# quality-check

## Purpose

Run linting, formatting checks, and R CMD check.

## When to use

- Before running the full test suite (typically before `regression-test`)
- Before merging/pushing

## Policy (rules)

Follow the quality policy here:

- `@.cursor/rules/quality-check.mdc`

## Commands

Use `make` commands (run `make help` for all options):

```bash
# Fast gate: schema validation + lint
make ci-fast

# Full CI: validate-schemas + lint + test + check
make ci

# Individual targets
make validate-schemas   # Validate YAML schemas
make lint               # Lint check (lintr)
make format             # Format (auto-fix with styler)
make check              # R CMD check (primary quality gate)

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

- `make check` passes with **0 errors, 0 warnings, 0 notes**

## Related rules

- `@.cursor/rules/quality-check.mdc`
