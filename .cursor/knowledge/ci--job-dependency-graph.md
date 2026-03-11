---
trigger: CI job, job dependency, filter category, coverage gate, coverage threshold, ci-pass, CI polling, poll interval, adaptive polling, time budget, CI wait, make coverage-check
---
# CI Job Dependency Graph

### PR CI (`ci.yaml`)

```
changes ──┬── validate-schemas  (r_source OR schemas)
          ├── format-check      (r_source)
          ├── lint              (r_source)
          ├── test              (r_source)
          ├── check             (r_source OR r_deps; --no-tests)
          ├── ci-config         (ci_config)
          ├── renv-check        (renv_deps)
          └── kb-validate       (kb_files)
                    │
               ci-pass (final gate, always runs)
```

All jobs depend only on `changes` and run in parallel.
`check` uses `--no-tests` flag — tests are handled by the dedicated `test` job.
Coverage is **not** on the PR critical path (see Main Push section below).
Final gate: `ci-pass` depends on all above; skipped jobs are treated as passing.

### Main Push (`R-CMD-check.yaml`)

```
R-CMD-check (5-matrix: macOS/Windows/Linux × R versions)
      │
      └── coverage (ubuntu-latest, R release)
            │
            └── [on failure] auto-Issue creation
```

Coverage runs post-merge on main. If coverage drops below threshold (80%), a template-compliant Issue is auto-created (or existing open Issue is updated with new evidence).

## Filter Categories

| Filter | Paths | Meaning |
|--------|-------|---------|
| `r_source` | `R/**`, `tests/**`, `DESCRIPTION`, `NAMESPACE` | R source code or test changes |
| `r_deps` | `renv.lock`, `.Rbuildignore` | Dependency or build-config changes |
| `schemas` | `docs/schemas/**`, `tools/validate-schemas.R` | Schema file changes |
| `ci_config` | `Makefile`, `tools/**`, `.github/workflows/**`, `containers/**`, `.pre-commit-config.yaml`, `.lintr` | CI/build infrastructure changes |
| `renv_deps` | `DESCRIPTION`, `renv.lock`, `renv/settings.json` | renv dependency changes |
| `kb_files` | `.cursor/knowledge/**`, `.cursor/rules/knowledge-index.mdc`, `AGENTS.md`, `.cursor/commands/pr-review.md` | Knowledge base changes |

## Job Trigger Conditions

| Job | Condition | Rationale |
|-----|-----------|-----------|
| `format-check` | `r_source` | Formatting applies only to R source files |
| `lint` | `r_source` | Linting applies only to R source files |
| `test` | `r_source` | Tests run only when source or tests change |
| `check` | `r_source OR r_deps` | R CMD check is affected by dependency and .Rbuildignore changes |
| `validate-schemas` | `schemas OR r_source` | Schema-code consistency requires both sides |
| `ci-config` | `ci_config` | CI infrastructure validation |
| `renv-check` | `renv_deps` | DESCRIPTION/renv.lock sync verification |
| `kb-validate` | `kb_files` | Knowledge base consistency (naming, frontmatter, index sync, review category sync) |

## Coverage Gate

Coverage enforcement runs on **main push** (`R-CMD-check.yaml`), not on PR CI. Threshold values are defined in `test-strategy.mdc` § Coverage Threshold Policy (SSOT for all coverage numbers). It runs `covr::package_coverage()` and fails if coverage is below the threshold. On failure, a template-compliant GitHub Issue is automatically created (with deduplication).

Local equivalent: `make coverage-check` (override with `COVERAGE_THRESHOLD=N`).

### Related PR workflows (separate from `ci.yaml`)

| Workflow | File | Trigger | Purpose |
|----------|------|---------|---------|
| `check-policy` | `pr-policy.yaml` | All PRs (unconditional) | PR body, labels, title format, base branch |
| `dependency-review` | `dependency-review.yaml` | PRs changing `DESCRIPTION` or `renv.lock` | Vulnerability scan |
| `auto-merge` | `dependabot-auto-merge.yaml` | Dependabot PRs only | Auto-merge minor dependency updates |

All `ci.yaml` jobs (except `ci-pass`) are conditional on path filters — they run only when matching files change. `ci-pass` always runs as the required status check aggregator.

## Adaptive Polling Strategy (SSOT)

This section is the **single source of truth** for CI polling intervals and time budgets. All other files (`pr-create.md`, `.cursor/templates/delegation--*.md`, etc.) reference this section instead of restating specific numbers.

Fixed-interval polling wastes time. Use a stage-aware strategy:

| Stage | Condition | Interval | Rationale |
|-------|-----------|----------|-----------|
| Early | No jobs completed | 20s | Initial queue + startup time |
| Mid | Any of lint/test/check still running | 15s | Parallel jobs in progress, longest is ~90s |
| Late | All of lint/test/check completed | 10s | Only ci-pass remains |
| Final | All except ci-pass | 5s | ci-pass completes in seconds |

**Time budget**: Use elapsed time (max 5 minutes) rather than poll count as the upper bound. Poll count limits (e.g., 10 polls) can expire before long jobs finish.

**Subagent delegation**: When delegating CI-wait to a subagent, include the job dependency graph in the prompt so the subagent can adapt its polling interval.
