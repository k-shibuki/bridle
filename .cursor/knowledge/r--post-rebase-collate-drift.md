---
trigger: rebase Collate, DESCRIPTION Collate, missing from Collate, roxygenise after rebase, R CMD check Collate
---
# Post-Rebase DESCRIPTION Collate Drift

After rebasing a feature branch onto a `main` that has gained new R files (from other merged PRs), the DESCRIPTION `Collate` field may be missing those files. R CMD check will fail with:

```
Error in .install_package_code_files(".", instdir) :
  files in '.../R' missing from 'Collate' field: .R
```

**Policy** (defined in `@.cursor/rules/quality-policy.mdc` § Post-Rebase Collate Drift): After every rebase with new R files, run `roxygen2::roxygenise()`, commit the updated DESCRIPTION/NAMESPACE, then proceed with `make format` and `make ci-fast`.

**Detection**: If `git diff origin/main --name-only` after rebase shows new `.R` files not authored by the current branch, roxygen regeneration is needed.
