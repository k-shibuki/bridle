---
trigger: S7 @include, cross-file class, Collate field, load order, object not found
---
# S7 `@include` Directive for Cross-File Class Dependencies

When an S7 class property references another S7 class defined in a different file, the source file should have an `@include` roxygen directive to guarantee load order (see `@.cursor/rules/quality-policy.mdc` § Type Strictness (S7) for the governing policy). Without it, the class definition may fail at load time depending on file collation order.

**Symptom**: `object 'ClassName' not found` during `roxygen2::roxygenise()` or `devtools::load_all()`.

**Pattern**: For every S7 property typed as another S7 class, verify:

1. The `#' @include <source-file>.R` directive exists in the file header
2. Run `roxygen2::roxygenise()` to update the Collate field

**Example**:

```r
#' @include context_schema.R
NULL

SessionContext <- S7::new_class("SessionContext",
  properties = list(
    schema = ContextSchema,
    ...
  )
)
```

**Why alphabetical order is unreliable**: Adding or removing files (including from other branches via rebase) changes the collation. Explicit `@include` is the only reliable mechanism.
