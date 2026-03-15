---
trigger: CI failure, CI check failed, failure classification, flaky test, CI rerun
---
# CI Failure Triage

When a CI check fails, classify the failure before acting:

| Category | Examples | Action |
|----------|----------|--------|
| **Code defect** | lint error, test failure, check warning | Fix locally, push, re-run CI |
| **Format drift** | format-verify diff | `make format`, commit, push |
| **Infrastructure** | Runner timeout, network error, container pull failure | Re-run workflow |
| **Policy** | check-policy rejects PR body | Update PR body (missing section, wrong format) |
| **Flaky** | Intermittent test failure not reproducible locally | Re-run once; if persistent, investigate |

**Evidence sources**: `make evidence-pull-request` provides `ci.status`
and `ci.checks[]` with per-job status. For detailed failure logs,
use the CI job URL from the checks array.
