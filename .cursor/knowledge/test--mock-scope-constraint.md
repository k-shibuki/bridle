---
trigger: local_mocked_bindings, mock scope, mock scope limitation, mock helper, mock calling environment
---
# Mock Scope Constraint: `local_mocked_bindings` cannot be extracted

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

**Exception**: Mock-applying wrappers like `with_scan_mocks` work correctly from `helper-mocks.R` because the `code` argument is lazily evaluated within the wrapper's frame where mocks are active. See `test-strategy.mdc` §7 (Helper Colocation).
