# debug

General-purpose debugging command. Policy: `@.cursor/rules/debug-strategy.mdc`

## Debug Method Priority

1. **reprex** — Create minimal reproducible example with `reprex::reprex()`
2. **browser() / debug()** — Interactive inspection when the failure point is known
3. **rlang::last_error() / last_trace()** — After an error, use `options(error = rlang::entrace)` then inspect
4. **testthat test** — Reproduce failure in `tests/testthat/test-*.R` for deterministic debugging

## Inputs

| Required | Error/stacktrace, repro steps, relevant `@R/` or `@tests/` files |
|----------|-------------------------------------------------------------------|
| Optional | `@docs/adr/`, `@R/...`, `@tests/testthat/...` |

---

## Task Prefix Convention

See `@.cursor/knowledge/agent--task-prefix-convention.md` for the naming convention.

---

## Workflow

| Step | Action |
|------|--------|
| 1. Symptom | Reproduce, state expected vs actual |
| 2. Hypotheses | List with IDs (`<TASK>-H1`, ...) |
| 3. Instrument | Add `message()` / `cli::cli_inform()` to verify hypotheses |
| 4. Validate | Adopted / Rejected with evidence |
| 5. Fix | Minimal change |
| 6. Verify | Run tests |

---

## Make Commands

All R commands run inside the development container (see `@.cursor/rules/workflow-policy.mdc` § Container Prerequisite).

```bash
make help    # Show available commands
make test    # Run tests
make check   # R CMD check (full validation)
make lint    # Lint check
make ci-fast # Fast gate: validate-schemas + renv-check + kb-validate + lint
make ci      # Full gate: validate-schemas + lint + test + check
```

---

## R Debugging Tools and Patterns

For R-specific debugging tools (reprex, browser, rlang), instrumentation templates, placement strategy, and phase-specific debugging guidance, see `@.cursor/knowledge/debug--method-priority.md` and `@.cursor/templates/debug--instrumentation.md`.

---

## Checklists

### Before Starting Debug

- [ ] Accurately described symptoms (expected vs actual)
- [ ] Listed hypotheses with task prefix (`<TASK>-H1`, ...)

### During Debug

- [ ] Added timeout to terminal commands
- [ ] Added region markers to instrumentation (`#region agent log`)
- [ ] Included hypothesis ID with task prefix in logs

### After Debug Completion

- [ ] Removed instrumentation code
- [ ] Identified root cause and made minimal fix
- [ ] Verified fix with tests
- [ ] Created report at `debug/docs/<TASK>_report.md` (if significant)

## Related

- `@.cursor/rules/debug-strategy.mdc` (policy)
- `@.cursor/commands/integration-design.md` (for preventing integration issues during new feature development)
