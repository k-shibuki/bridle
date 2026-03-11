# test-regression

## Purpose

Run tests in three stages to detect regressions efficiently:

1. Run tests for files changed in this session (fast, scoped)
2. Run the full test suite (final gate)
3. Verify coverage meets the threshold

**All three stages are required.** Stage 1 alone is not sufficient—always run Stages 2 and 3 as the final gates.

## When to use

- After quality checks pass (typically after `quality-check`)
- Before merging/pushing changes

## Inputs

- None required (but attach failing logs/output if rerunning after a failure)

## How to run (recommended)

Ensure the `bridle-dev` container is running (`make container-up`; verify with `make doctor`). All R commands run there (see `@.cursor/rules/workflow-policy.mdc` § Container Prerequisite).
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

> **IMPORTANT:** If any test fails in Stage 2, you must fix it before proceeding. Do not ignore failures even if they appear unrelated to your changes. See "Failure handling policy" below.

### Stage 3: coverage gate

After all tests pass, verify that line coverage meets the project threshold (see `test-strategy.mdc` § Coverage Threshold Policy for current values):

```bash
make coverage-check
```

To override the threshold (e.g., during initial adoption):

```bash
make coverage-check COVERAGE_THRESHOLD=70
```

If coverage is below the threshold, add tests before proceeding. Do not lower the threshold to pass the gate.

## Output (response format)

- **Summary**: passed / failed / skipped
- **Failures** (if any): list + first actionable traceback snippets

## Failure handling policy

Per `@.cursor/rules/agent-safety.mdc` `HS-NO-DISMISS`: every test failure is a defect to fix. The test suite must pass completely (zero failures) before proceeding to commit/push. When failures occur: identify the root cause, fix it, and only create a follow-up task if there is a documented technical blocker (e.g., external dependency issue).
