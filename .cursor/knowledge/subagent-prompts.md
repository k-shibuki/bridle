# Subagent Prompt Templates

Reusable prompt templates for delegating blocking operations to background subagents.

**Policy**: See `@.cursor/rules/ai-guardrails.mdc` § Subagent Delegation for enforceable requirements.

---

## Required Prompt Elements

Every delegated subagent prompt MUST include:

1. **Goal**: One-sentence summary
2. **Steps**: Numbered steps with exact shell commands
3. **Prohibitions**: Explicit list of forbidden operations
4. **Error handling**: What to do on failure
5. **Return format**: What to report on completion

---

## Template: CI-Wait + Merge

```
## Goal
Monitor CI for PR #<N> until all checks pass, then merge it.

## Steps

1. Poll CI status (adaptive intervals, max 5 minutes elapsed):
   - Early: `sleep 20 && gh pr checks <N>`
   - After format-check + lint pass: `sleep 15 && gh pr checks <N>`
   - After test passes: `sleep 10 && gh pr checks <N>`

2. When all checks pass:
   `gh pr merge <N> --squash --delete-branch`

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

## Return format
Report: "MERGED: PR #<N> squash-merged at <sha>" or "FAILED: <reason>"
```

---

## Template: Sequential PR Merge Chain

```
## Goal
Merge PRs #<A>, #<B>, #<C> sequentially (each depends on the previous).

## Steps

For each PR in order:
1. Rebase onto main: `gh pr view <N> --json headRefName -q '.headRefName'` then verify it's up to date
2. Wait for CI: poll with `gh pr checks <N>` (max 5 min per PR)
3. Merge: `gh pr merge <N> --squash --delete-branch`
4. Verify merge: `gh pr view <N> --json state -q '.state'`
5. Proceed to next PR

## Prohibitions
- Do NOT run `git checkout`, `git switch`, `git branch`, or `git rebase`
- Do NOT modify any files
- Use only `gh` CLI commands and `sleep`

## Error handling
- If CI fails on PR #X: stop the chain, report which PR failed and why
- If merge conflict: stop the chain, report the conflict

## Return format
Report: "COMPLETED: Merged PRs #A, #B, #C" or "STOPPED at PR #X: <reason>"
```

---

## Template: CI-Wait Only (No Merge)

Use when the main agent wants to merge manually but needs CI monitoring.

```
## Goal
Monitor CI for PR #<N> and report when all checks complete.

## Steps
1. Poll CI status (adaptive intervals, max 5 minutes elapsed):
   `sleep 20 && gh pr checks <N>`
2. When all checks pass or any check fails, report the final status.

## Prohibitions
- Do NOT run `git checkout`, `git switch`, `git branch`, or `git rebase`
- Do NOT run `gh pr merge`
- Do NOT modify any files

## Return format
Report: "CI PASSED: all checks green for PR #<N>" or "CI FAILED: <check-name> failed — <details>"
```

---

## Subagent Configuration Reference

| Use case | `subagent_type` | `model` | `run_in_background` |
|----------|-----------------|---------|---------------------|
| CI poll + merge | `shell` | `fast` | `true` |
| Sequential merge chain | `shell` | `fast` | `true` |
| CI poll only | `shell` | `fast` | `true` |

---

## Completion Detection

The main agent detects subagent completion by reading the subagent transcript `.jsonl` file:

1. Read the last few lines of the transcript file
2. Parse the last `assistant` message for a result summary
3. If still running (no final summary): note "background task in progress", continue independent work
4. If completed successfully: incorporate results and proceed
5. If error encountered: report to the user
