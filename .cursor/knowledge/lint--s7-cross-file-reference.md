---
trigger: object_usage_linter S7, S7 constructor lint, no visible global function, cross-file S7
---
# `object_usage_linter` and S7 Cross-File References

`lintr`'s `object_usage_linter` does not resolve S7 class constructors defined in other files within the same package. References like `ParameterInfo(...)` or `ScanResult(...)` in a file that does not define them will be flagged as "no visible global function definition."

**Resolution**: Apply `# nolint: object_usage_linter.` at the specific line with a reason comment. This is a known lintr limitation with S7, not a code defect.

```r
result <- ScanResult(...) # nolint: object_usage_linter. S7 class defined in R/scan_result.R
```
