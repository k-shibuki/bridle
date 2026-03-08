---
trigger: NULL assignment, list element removal, missing formal, empty symbol, formals extraction, sentinel pattern
---
# NULL Assignment Trap in R

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
