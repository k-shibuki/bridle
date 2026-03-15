---
trigger: lint CI local divergence, object_usage_linter false positive, getNamespace failure, lintr environment, CI lint passes locally fails, renv out-of-sync lint, pkgload load_all lint
---
# Lint CI-Local Environment Divergence

## Root Cause

`lintr::object_usage_linter` resolves function visibility via `getNamespace(pkg_name)`:

- **Success** (package installed/loaded): exports are visible → no false positives
- **Failure** (package not installed): falls back to `globalenv()` → package-exported functions appear as "no visible global function definition"

### Why CI and local differ

| Environment | Package state | `getNamespace("bridle")` | Result |
|---|---|---|---|
| CI (`r-lib/actions/setup-r-dependencies`) | `bridle` installed as `local::` | Succeeds | Exports visible |
| Local container (renv) | `bridle` NOT installed | Fails → `globalenv()` | False-positive warnings |

The key function is `lintr:::make_check_env()`:

```r
if (!is.null(pkg_name)) {
  parent_env <- try_silently(getNamespace(pkg_name))
}
if (is.null(pkg_name) || inherits(parent_env, "try-error")) {
  parent_env <- globalenv()  # fallback: exports not visible
}
```

## Solution

`make lint` calls `pkgload::load_all()` before `lintr::lint_package()`, making the package namespace available:

```make
lint: _require_container
 $(RSCRIPT) -e "pkgload::load_all('.', quiet = TRUE); lintr::lint_package()"
```

After `load_all()`, `getNamespace("bridle")` succeeds in both environments.

## Implications for `# nolint` annotations

With `load_all()` in place, `object_usage_linter` false positives for **package-exported functions** are eliminated. The `make_graph_engine` nolint annotation (added in #142) was removed as part of this fix.

S7 constructor annotations **remain necessary** — S7 constructors are not standard exports and lintr cannot resolve them even with `load_all()`. The accepted pattern is: `# nolint: object_usage_linter. S7 constructor`
