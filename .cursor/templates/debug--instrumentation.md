# Template: R Instrumentation and Boundary Placement

## Instrumentation Template

```r
# #region agent log
cli::cli_inform("H1: {.field location} {.val {value}}", location = "R/foo.R:bar()")
# or
message(sprintf("[%s] H1: %s = %s", Sys.time(), "location", value))
# #endregion
```

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
