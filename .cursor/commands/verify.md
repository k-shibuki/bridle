# verify

## Reads

- `quality-policy.mdc` (execution order, nolint policy, type strictness, definition of done)
- `test-strategy.mdc` § Coverage Threshold Policy
- If nolint needed: `lint--nolint-accepted-patterns.md` (per `HS-NOLINT`)
- If lint issues: `lint--styler-lintr-conflict.md`, `lint--s7-cross-file-reference.md`, `lint--ci-local-divergence.md`

## Sense

None required (uses local file state).

## Act

1. `make format` then `make format-verify`
2. `make lint` — fix all findings
3. `make check` — require 0 errors, 0 warnings, 0 notes
4. `make test` — full suite, zero failures
5. `make coverage-verify`
6. `make schema-validate` (if schema files changed)
7. `make document` (if roxygen2 comments changed)

When no R code changed (Makefile, docs, CI only) but schema-related files were modified, run `make schema-validate` only. The `pre-push` hook enforces the appropriate subset automatically.

## Output

- Issues found + fixes applied (grouped by tool)
- Intentional exceptions with justification
- Coverage summary (pass/fail + percentage)

## Guard

- `HS-NO-DISMISS`: every diagnostic is a defect to fix
- `HS-NOLINT`: consult Knowledge before any nolint
- `HS-LOCAL-VERIFY`: pre-push hook validates on push
