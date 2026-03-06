# debug

General-purpose debugging command. Policy: `@.cursor/rules/debug.mdc`

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

**Multiple AI agents may debug concurrently.** Use consistent prefixes:

| Artifact | Pattern | Example |
|----------|---------|---------|
| Docs | `debug/docs/<TASK>_report.md` | `debug/docs/GRAPH_report.md` |
| Logs | `debug/scripts/<TASK>_debug.log` | `debug/scripts/NODE_debug.log` |
| Hypothesis IDs | `<TASK>-H1`, `<TASK>-H2`, ... | `GRAPH-H1`, `EVAL-H2` |

Common prefixes: `GRAPH`, `NODE`, `RULE`, `EVAL`, `LLM`, `MCP`, `SCHEMA`

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

All R commands run inside the development container. Ensure it is running (`make container-up`).

```bash
make help    # Show available commands
make test    # Run tests
make check   # R CMD check (full validation)
make lint    # Lint check
make ci-fast # Quick gate: validate-schemas + lint
make ci      # Full gate: validate-schemas + lint + test + check
```

---

## R Debugging Tools

### reprex

```r
reprex::reprex({
  # Minimal code that reproduces the bug
  x <- something_that_fails()
})
```

### browser()

```r
# Add to code where you want to pause
browser()
# Then: n (next), c (continue), Q (quit)
```

### rlang error inspection

```r
options(error = rlang::entrace)
# Run failing code, then:
rlang::last_error()
rlang::last_trace()
```

---

## Phase-specific Debugging (bridle layers)

| Layer | Goal | Check |
|-------|------|-------|
| Layer 1: Framework | S7 classes, decision_graph/node/rule | `make test`, `make check` |
| Layer 2: Schema | Parameter extraction, formals() | Unit tests for schema functions |
| Layer 3: Domain graph | Plugin integration | Integration tests |

---

## Instrumentation

### Philosophy

**No limit on log count.** Add enough to track propagation and debug in one run.

### Log location

`debug/scripts/<TASK>_debug.log` — **NOT** `.cursor/debug.log`

### Template (R)

```r
# #region agent log
cli::cli_inform("H1: {.field key} = {.val {value}}")
# #endregion
```

### Cleanup

```bash
grep -rn "# #region agent log" R/
```

---

## References

| Path | Purpose |
|------|---------|
| `docs/adr/` | Architecture decisions |
| `debug/docs/` | Past debug reports |
| `R/` | Package source code |

---

## Related

- `@.cursor/rules/debug.mdc` (policy)
- `@.cursor/commands/integration-design.md` (for preventing integration issues during new feature development)
