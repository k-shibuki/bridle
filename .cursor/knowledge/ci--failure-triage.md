---
trigger: CI failure, CI check failed, run view log-failed, failure classification
---
# CI Failure Triage

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
