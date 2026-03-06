# CI Pipeline Knowledge

CI job dependencies, polling strategies, and failure classification for the bridle project.

**Policy**: See `@.cursor/rules/ai-guardrails.mdc` for CI-related Hard Stops.

---

## Job Dependency Graph

```
changes ──┬── validate-schemas
          ├── format-check
          ├── lint
          │
          └── test ──┬── check
                     └── coverage
                              │
                         ci-pass (final gate)
```

Independent jobs (can run in parallel): `validate-schemas`, `format-check`, `lint`
Sequential jobs: `test` depends on setup; `check` and `coverage` depend on `test`
Final gate: `ci-pass` depends on all above

### Coverage Gate

The `coverage` job enforces a minimum line coverage threshold (80%). It runs `covr::package_coverage()`, uploads results to Codecov, and then fails if coverage is below the threshold. This is independent of Codecov's own status checks — the CI gate works even if Codecov is not configured.

Local equivalent: `make coverage-check` (default threshold 80%, override with `COVERAGE_THRESHOLD=N`).

Configuration: `codecov.yml` at repo root defines project target (80%), patch target (90%), and ignored paths.

Additional checks (PR-only): `check-policy`, `dependency-review`
Skippable: `ci-config`, `auto-merge`

---

## Adaptive Polling Strategy

Fixed-interval polling wastes time. Use a stage-aware strategy:

| Stage | Condition | Interval | Rationale |
|-------|-----------|----------|-----------|
| Early | No jobs completed | 20s | Initial queue + startup time |
| Mid | format-check + lint pass | 15s | test is running, takes ~70s |
| Late | test passes | 10s | check/coverage are the last jobs, ~90s each |
| Final | All except ci-pass | 5s | ci-pass completes in seconds |

**Time budget**: Use elapsed time (max 5 minutes) rather than poll count as the upper bound. Poll count limits (e.g., 10 polls) can expire before long jobs finish.

**Subagent delegation**: When delegating CI-wait to a subagent, include the job dependency graph in the prompt so the subagent can adapt its polling interval.

---

## Failure Classification

When a CI check fails, classify the failure before acting:

| Category | Examples | Action |
|----------|----------|--------|
| **Code defect** | lint error, test failure, check warning | Fix locally, push, re-run CI |
| **Format drift** | format-check diff | Run `make format`, commit, push |
| **Infrastructure** | Runner timeout, network error, container pull failure | Re-run the workflow via GitHub UI or `gh run rerun` |
| **Policy** | check-policy rejects PR body | Update PR body (missing section, wrong format) |
| **Flaky** | Intermittent test failure not reproducible locally | Re-run once; if persistent, investigate |

**Key diagnostic commands**:

```bash
gh pr checks <N>                    # Overview of all checks
gh run view <run-id> --log-failed   # Failed job logs
```
