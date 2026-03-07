# Snapshot Testing Guidelines (testthat 3)

## When to Use Snapshots

Use `expect_snapshot()` and `expect_snapshot_error()` for:

- **Complex validation messages** where regex matching is fragile (e.g., `validate_plugin()` multi-line error output)
- **Structured object printing** (e.g., S7 class `print()` output) where exact format matters
- **Multi-line output** that would require multiple `expect_match()` calls

Do NOT use snapshot tests for:

- Simple string comparisons (`expect_equal()` is more explicit)
- Frequently changing output (snapshots become maintenance burden)

## Managing `_snaps/` Directories

- Snapshot files live in `tests/testthat/_snaps/<test-file-name>/`.
- They MUST be committed to version control.
- On snapshot changes, review the diff carefully — snapshot updates should be intentional.
- Use `testthat::snapshot_review()` to interactively approve changes.
