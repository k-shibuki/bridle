---
trigger: mock external function, mock system function, namespace locking, packageVersion mock
---
# Mocking System and External Functions

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

This applies to all external dependencies (ellmer, ragnar, vitals). Wrap the external call in a package function, then mock the wrapper.
