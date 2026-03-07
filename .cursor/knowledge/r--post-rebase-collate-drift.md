---
trigger: rebase Collate, DESCRIPTION Collate, missing from Collate, roxygenise after rebase
---
# Post-Rebase DESCRIPTION Collate Drift

After rebasing a feature branch onto a `main` that has gained new R files (from other merged PRs), the DESCRIPTION `Collate` field may be missing those files. R CMD check will fail with:

```
Error in .install_package_code_files(".", instdir) :
  files in '.../R' missing from 'Collate' field: .R
```

**Rule**: After every `git rebase` that incorporates new R source files:

1. Run `roxygen2::roxygenise()` (updates Collate and NAMESPACE)
2. Commit the updated DESCRIPTION and NAMESPACE
3. Then proceed with `make format` and `make ci-fast`

**Detection**: If `git diff origin/main --name-only` after rebase shows new `.R` files not authored by the current branch, roxygen regeneration is needed.
