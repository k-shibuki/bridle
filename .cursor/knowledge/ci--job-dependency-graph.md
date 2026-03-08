---
trigger: CI job, job dependency, filter category, coverage gate, coverage threshold, ci-pass, CI polling, poll interval, adaptive polling, time budget, CI wait, make coverage-check
---
# CI Job Dependency Graph

```
changes ──┬── validate-schemas  (r_source OR schemas)
          ├── format-check      (r_source)
          ├── lint              (r_source)
          │     │
          │     └── test        (r_source)
          │           │
          │           ├── check    (r_source OR r_deps; runs even if test was skipped)
          │           │
          │           └── coverage (r_source)
          │
          └── ci-config         (ci_config)
                    │
               ci-pass (final gate, always runs)
```

Independent jobs (can run in parallel): `validate-schemas`, `format-check`, `lint`, `ci-config`
Sequential chain: `lint` → `test` → `check` → `coverage`
Special case: `check` uses `always()` so it runs when `test` is skipped (r_deps-only changes)
Final gate: `ci-pass` depends on all above; skipped jobs are treated as passing

## Filter Categories

| Filter | Paths | Meaning |
|--------|-------|---------|
| `r_source` | `R/**`, `tests/**`, `DESCRIPTION`, `NAMESPACE` | R source code or test changes |
| `r_deps` | `renv.lock`, `.Rbuildignore` | Dependency or build-config changes |
| `schemas` | `docs/schemas/**`, `tools/validate-schemas.R` | Schema file changes |
| `ci_config` | `Makefile`, `tools/**`, `.github/workflows/**`, `containers/**`, `.pre-commit-config.yaml`, `.lintr` | CI/build infrastructure changes |

## Job Trigger Conditions

| Job | Condition | Rationale |
|-----|-----------|-----------|
| `format-check` | `r_source` | Formatting applies only to R source files |
| `lint` | `r_source` | Linting applies only to R source files |
| `test` | `r_source` | Tests run only when source or tests change |
| `check` | `r_source OR r_deps` | R CMD check is affected by dependency and .Rbuildignore changes |
| `coverage` | `r_source` | Coverage only changes when source code changes |
| `validate-schemas` | `schemas OR r_source` | Schema-code consistency requires both sides |
| `ci-config` | `ci_config` | CI infrastructure validation |

## Coverage Gate

The `coverage` job enforces minimum line coverage. Threshold values are defined in `test-strategy.mdc` § Coverage Threshold Policy (SSOT for all coverage numbers). It runs `covr::package_coverage()`, uploads results to Codecov, and then fails if coverage is below the threshold. This is independent of Codecov's own status checks — the CI gate works even if Codecov is not configured.

Local equivalent: `make coverage-check` (override with `COVERAGE_THRESHOLD=N`).

Configuration: `codecov.yml` at repo root defines project and patch targets and ignored paths.

Additional checks (PR-only): `check-policy`, `dependency-review`
Skippable: `ci-config`, `auto-merge`

## Adaptive Polling Strategy (SSOT)

This section is the **single source of truth** for CI polling intervals and time budgets. All other files (`pr-create.md`, `agent--delegation-templates.md`, etc.) reference this section instead of restating specific numbers.

Fixed-interval polling wastes time. Use a stage-aware strategy:

| Stage | Condition | Interval | Rationale |
|-------|-----------|----------|-----------|
| Early | No jobs completed | 20s | Initial queue + startup time |
| Mid | format-check + lint pass | 15s | test is running, takes ~70s |
| Late | test passes | 10s | check/coverage are the last jobs, ~90s each |
| Final | All except ci-pass | 5s | ci-pass completes in seconds |

**Time budget**: Use elapsed time (max 5 minutes) rather than poll count as the upper bound. Poll count limits (e.g., 10 polls) can expire before long jobs finish.

**Subagent delegation**: When delegating CI-wait to a subagent, include the job dependency graph in the prompt so the subagent can adapt its polling interval.
