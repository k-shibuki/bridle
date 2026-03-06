# regression-test

## Purpose

Run tests in two stages to detect regressions efficiently:

1. Run tests for files changed in this session (fast, scoped)
2. Run the full test suite (final gate)

**Both stages are required.** Stage 1 alone is not sufficient—always run Stage 2 as the final gate.

## When to use

- After quality checks pass (typically after `quality-check`)
- Before merging/pushing changes

## Inputs

- None required (but attach failing logs/output if rerunning after a failure)

## How to run (recommended)

All R commands execute inside the development container. Ensure it is running (`make container-up`).
Use `make` commands (run `make help` for all options).

### Stage 1: session-scoped tests (recommended)

Run tests for the modules you changed. Use a filter when you know the affected area:

```bash
# Run tests matching a filter (e.g., by file/context name)
Rscript -e "devtools::test(filter = 'decision_graph')"

# Or run all tests
make test
```

If you changed implementation code but didn't touch tests, choose the smallest relevant filter (e.g., `decision_graph`, `node`, `rule`) or run the full suite.

### Stage 2: full suite (final gate)

Run the full test suite to catch regressions outside your local change surface:

```bash
make test
```

With coverage (optional):

```bash
make coverage
```

> **IMPORTANT:** If any test fails in Stage 2, you must fix it before proceeding. Do not ignore failures even if they appear unrelated to your changes. See "Failure handling policy" below.

## Output (response format)

- **Summary**: passed / failed / skipped
- **Failures** (if any): list + first actionable traceback snippets

## Failure handling policy

**CRITICAL: Do NOT ignore test failures, even if they appear unrelated to your changes.**

- All test failures must be addressed before merging/pushing
- If a test failure is pre-existing (not introduced by your changes):
  - Fix it as part of this commit, or
  - Document why it cannot be fixed now and create a follow-up task
- Do NOT report failures as "unrelated" or "pre-existing" without fixing them
- The test suite must pass completely (zero failures) before proceeding to commit/push

### When you encounter failures

1. **Identify the root cause**: Check if your changes introduced the failure
2. **Fix immediately**: If your changes caused it, fix the regression
3. **Fix pre-existing issues**: If the failure existed before your changes, fix it now
4. **Document exceptions**: Only skip fixing if there's a documented technical blocker (e.g., external dependency issue), and create a follow-up task
