# R Testing Patterns

R-specific testing gotchas and patterns accumulated during bridle development.

**Policy**: See `@.cursor/rules/test-strategy.mdc` for enforceable test requirements.

---

## `local_mocked_bindings` Scope Constraint

`testthat::local_mocked_bindings()` uses the calling environment for scope. This means:

- It **cannot be extracted into a reusable helper function** — the mock would be scoped to the helper's environment, not the `test_that` block.
- Each `test_that` block must call `local_mocked_bindings()` directly.

**Pattern**: Create a helper that returns mock values, then apply them inline:

```r
mock_values <- function() {
  list(
    get_rd_db = function(pkg) list(),
    resolve_function = function(pkg, fn) identity
  )
}

test_that("my test", {
  mocks <- mock_values()
  local_mocked_bindings(
    get_rd_db = mocks$get_rd_db,
    resolve_function = mocks$resolve_function
  )
  # ... test code ...
})
```

---

## Missing Formals and the NULL Assignment Trap

R function formals can be "missing" (no default value). `formals()` returns these as empty symbols, which cause errors when passed to other functions via `lapply` or similar.

**Problem**: `list[[name]] <- NULL` removes the element from the list instead of setting it to `NULL`.

```r
result[["param"]] <- NULL
length(result)  # one fewer element — silent data loss

result["param"] <- list(NULL)
length(result)  # correct — element preserved with NULL value
```

**Recommended pattern**: Use a sentinel object to distinguish "no default" from "default is NULL":

```r
.missing_sentinel <- structure(list(), class = "bridle_missing_formal")

safe_formals <- function(fmls) {
  result <- vector("list", length(fmls))
  names(result) <- names(fmls)
  for (nm in names(fmls)) {
    val <- fmls[[nm]]
    if (is.symbol(val) && identical(deparse(val), "")) {
      result[nm] <- list(.missing_sentinel)
    } else {
      result[nm] <- list(val)
    }
  }
  result
}
```

---

## Primitive Functions and `body()`

`body(fn)` returns `NULL` for both primitive functions and simple mock functions like `function() NULL`. When writing code that inspects function bodies (e.g., scanner Layer 3a):

**Pattern**: Check `is.primitive(fn)` first:

```r
if (is.primitive(fn)) {
  warning("Cannot analyze source for primitive: ", fn_name)
  return(result)
}
fn_body <- body(fn)
if (is.null(fn_body)) {
  return(result)  # silently skip non-primitive with NULL body (e.g., mocks)
}
```

---

## Layered Architecture Mock Strategy

When a function calls multiple layers sequentially (e.g., `scan_package()` calls `scan_layer1`, `scan_layer2`, `scan_layer3a`):

1. **Unit tests for each layer**: Test each `scan_layerN()` function independently, mocking only that layer's external dependencies.
2. **Integration tests for the orchestrator**: When testing `scan_package()`, mock **all** layer boundaries (e.g., `get_rd_db`, `resolve_function`) even if only testing Layer 1 behavior — otherwise Layer 2/3 code paths emit warnings or errors from unmocked dependencies.
3. **Update mocks when adding layers**: Adding a new layer to the orchestrator requires updating the shared mock helper (e.g., `with_scan_mocks`) in integration tests.

**Anti-pattern**: Testing `scan_package()` without mocking downstream layers, assuming "Layer 1 tests don't need Layer 2 mocks."

---

## Mocking System and External Functions

Functions like `utils::packageVersion()`, `base::system()`, or external package functions cannot be directly mocked due to namespace locking.

**Pattern**: Create a thin wrapper in your package and mock the wrapper:

```r
# In R/helpers.R
get_package_version <- function(pkg) {
  utils::packageVersion(pkg)
}

# In tests
local_mocked_bindings(
  get_package_version = function(pkg) package_version("1.0.0")
)
```

---

## S7 Constructor Testing

When testing S7 classes:

- **Validator error messages**: Use `expect_error(..., "expected substring")` to verify the validator produces the right message. S7 validators typically use `sprintf()` or `paste()` for messages; match a stable substring.
- **Property type constraints**: Test that assigning a wrong type produces a clear error. S7 enforces types at construction time, so `expect_error(MyClass(field = wrong_type))` is sufficient.
- **Default values**: Explicitly test that omitted properties take the documented default. Do not assume defaults are correct without verification.
