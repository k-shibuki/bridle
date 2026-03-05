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
# Lint check (lintr)
make lint

# Format (auto-fix with styler)
make style

# R CMD check (primary quality gate)
make check

# Run all: lint + style + check
make lint && make style && make check
```

## Output (response format)

- **Issues found**: grouped by tool/code
- **Fixes applied**: summary + file list
- **Intentional exceptions**: list + reason

## Definition of Done

- `make check` passes with **0 errors, 0 warnings, 0 notes**

## Related rules

- `@.cursor/rules/quality-check.mdc`
