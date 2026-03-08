---
trigger: Suggests package, getFromNamespace, optional dependency, requireNamespace, R CMD check Suggests
---
# Suggests Package Dynamic Loading Pattern

When a package is in `Suggests` (not `Imports`), calling `pkg::fn()` directly triggers an R CMD check warning ("'::' or ':::' import not declared from").

**Pattern**: Use `utils::getFromNamespace()` for dynamic access:

```r
bridle_chat <- function(...) {
  if (!requireNamespace("ellmer", quietly = TRUE)) {
    stop("Package 'ellmer' is required. Install with install.packages('ellmer').")
  }
  chat_fn <- utils::getFromNamespace("chat", "ellmer")
  chat_fn(...)
}
```

This keeps the dependency optional while passing R CMD check cleanly.
