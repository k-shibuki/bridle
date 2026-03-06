# R Debugging Patterns

R-specific debugging techniques and instrumentation patterns for the bridle project.

**Policy**: See `@.cursor/rules/debug.mdc` for enforceable debugging requirements.

---

## Debug Method Priority

1. **reprex** — Create minimal reproducible example with `reprex::reprex()`; isolate the issue
2. **browser() / debug()** — Interactive inspection when the failure point is known
3. **rlang::last_error() / last_trace()** — After an error, inspect with `options(error = rlang::entrace)`
4. **testthat test** — Reproduce failure in `tests/testthat/test-*.R` for deterministic debugging

---

## Instrumentation Template (R)

```r
# #region agent log
cli::cli_inform("H1: {.field location} {.val {value}}", location = "R/foo.R:bar()")
# or
message(sprintf("[%s] H1: %s = %s", Sys.time(), "location", value))
# #endregion
```

---

## Placement Strategy (Propagation Tracking)

For debugging value propagation issues, add instrumentation at each boundary:

```
[Entry point] → [Transform 1] → [Transform 2] → [Exit point]
     ↓               ↓               ↓               ↓
   H1-L1           H1-L2           H1-L3           H1-L4
```

| Location | What to log |
|----------|-------------|
| Entry point | Raw input values |
| Each transform | Before/after values, which branch taken |
| Exit point | Final output values |
| Error handlers | Exception type, message, context |

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

## R-Specific Notes

### NSE (Non-Standard Evaluation)

- When debugging `dplyr`-like or `rlang` idioms, ensure `enquo()` / `{{ }}` are evaluated correctly
- Use `rlang::last_error()` and `rlang::last_trace()` after `options(error = rlang::entrace)`

### S7 Classes

- `@` vs `prop()`: R < 4.3.0 may need `prop()` for property access
- Validators run at construction; use `browser()` inside validator to inspect failing values

### reprex best practices

- `reprex::reprex()` creates minimal reproducible examples
- Use when the bug is reproducible but the cause is unclear; share output for collaboration

---

## Phase-Specific Debugging (bridle layers)

| Layer | Goal | Check |
|-------|------|-------|
| Layer 1: Framework | S7 classes, decision_graph/node/rule | `make test`, `make check` |
| Layer 2: Schema | Parameter extraction, formals() | Unit tests for schema functions |
| Layer 3: Domain graph | Plugin integration | Integration tests |
