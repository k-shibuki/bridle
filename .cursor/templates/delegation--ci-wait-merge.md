# Template: CI-Wait + Merge (Fallback)

**Use only when `gh pr merge --auto` fails** (e.g., token scope issue, API error).
For the normal case, use auto-merge directly.

**Prerequisite**: `pr-review` has completed and concluded "Mergeable". For CI
polling before review, use `delegation--ci-wait-only.md`.

```text
## Goal
Monitor CI for PR #<N> until all checks pass, then merge it.

## Steps

1. Poll CI status using Adaptive Polling Strategy from `ci--job-dependency-graph.md` § Adaptive Polling Strategy (SSOT for intervals and time budgets):
   - Adapt poll intervals based on which jobs have completed
   - Use elapsed time (max 5 min) as upper bound

2. When all checks pass:
   `gh pr merge <N> --squash`

3. After merge, verify:
   `gh pr view <N> --json state -q '.state'`

## Prohibitions
- Do NOT run `git checkout`, `git switch`, `git branch`, or `git rebase`
- Do NOT modify any files
- Use only `gh` CLI commands and `sleep`

## Error handling
- If a check fails: `gh run view <run-id> --log-failed`, report the failure details
- If check-policy fails: report that the PR body needs updating
- If merge fails due to conflicts: report the conflict, do NOT attempt resolution
- If merge blocked by unresolved review threads: report "BLOCKED: unresolved review threads — run review-fix per review--comment-response.md"

## Return format
Report: "MERGED: PR #<N> squash-merged at <sha>" or "FAILED: <reason>"
```
