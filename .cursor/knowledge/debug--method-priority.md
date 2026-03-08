---
trigger: debug method, reprex, R browser(), rlang last_error, last_trace, rlang entrace, R debugging, debug priority
---
# Debug Method Priority and R Tools Reference

## Priority Order

1. **reprex** — Create minimal reproducible example with `reprex::reprex()`; isolate the issue
2. **browser() / debug()** — Interactive inspection when the failure point is known
3. **rlang::last_error() / last_trace()** — After an error, inspect with `options(error = rlang::entrace)`
4. **testthat test** — Reproduce failure in `tests/testthat/test-*.R` for deterministic debugging

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

## R-Specific Notes

### NSE (Non-Standard Evaluation)

- When debugging `dplyr`-like or `rlang` idioms, ensure `enquo()` / `{{ }}` are evaluated correctly
- Use `rlang::last_error()` and `rlang::last_trace()` after `options(error = rlang::entrace)`

### S7 Classes

- `@` vs `prop()`: R < 4.3.0 may need `prop()` for property access
- Validators run at construction; use `browser()` inside validator to inspect failing values

## Phase-Specific Debugging (bridle layers)

| Layer | Goal | Check |
|-------|------|-------|
| Layer 1: Framework | S7 classes, decision_graph/node/rule | `make test`, `make check` |
| Layer 2: Schema | Parameter extraction, formals() | Unit tests for schema functions |
| Layer 3: Domain graph | Plugin integration | Integration tests |
