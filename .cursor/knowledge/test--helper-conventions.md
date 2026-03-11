---
trigger: helper-mocks.R, test helper, helper file, setup.R, test data builder, mock factory, helper colocation, helper naming
---
# Test Helper Conventions

## Helper files (`tests/testthat/helper-*.R`)

testthat automatically sources all `helper-*.R` files before running tests. Use them for **shared mock value factories** and **test data builders**.

- **`helper-mocks.R`**: Contains mock value factories (e.g., `mock_resolve()`, `mock_version()`, `make_mock_rd()`, `mock_crossref_response()`) and test data builders (e.g., `make_graph()`, `make_knowledge()`).
- Helpers provide **values only**. `local_mocked_bindings()` must always be called inline in each `test_that` block due to scope constraints (see `test-strategy.mdc` § Mock/Patch Conventions).
- When adding new mock patterns, check `helper-mocks.R` first. Add to the helper if the pattern will be reused across multiple test files. Keep file-specific helpers in the test file itself.
- **Colocation rule**: If a helper function references other helpers from `helper-mocks.R` (including mock-applying wrappers like `with_scan_mocks`), it MUST be defined in `helper-mocks.R` — not in the test file. This ensures `object_usage_linter` can resolve all references without `# nolint`. `# nolint` suppresses the diagnostic but does not prove the reference is valid — co-location makes the dependency explicit and verifiable by the linter.

## Setup file (`tests/testthat/setup.R`)

Sourced once before all tests. Use for prerequisites like `skip_if_not_installed()` and global test options. Do not define test data or mock values here.

## Naming conventions

| File | Purpose | Auto-sourced |
|------|---------|-------------|
| `helper-mocks.R` | Shared mock factories and test builders | Yes, before each test file |
| `setup.R` | One-time prerequisites and skip conditions | Yes, once before all tests |
| Test-file-local helpers | Helpers specific to one test file | Defined at top of test file |
