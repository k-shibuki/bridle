---
trigger: CI-wait template, CI-wait only, merge template, sequential merge, dependent PR merge, delegation template, subagent prompt template, background subagent
---
# Subagent Delegation Templates

Four reusable templates for delegating blocking operations to background subagents.

## Template 1: CI-Wait + Merge

**Prerequisite**: Use only after `pr-review` has completed and concluded "Mergeable". For CI polling before review, use Template 3 (CI-Wait Only).

```
## Goal
Monitor CI for PR #<N> until all checks pass, then merge it.

## Steps

1. Poll CI status using Adaptive Polling Strategy from `ci--job-dependency-graph.md` § Adaptive Polling Strategy (SSOT for intervals and time budgets):
   - Adapt poll intervals based on which jobs have completed
   - Use elapsed time (max 5 min) as upper bound

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

## Template 2: Sequential PR Merge Chain

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

## Template 3: CI-Wait Only (No Merge)

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

## Template 4: Dependent PR Merge Chain (rebase-enabled)

```
## Goal
Merge PRs #<A> and #<B> sequentially. #<B> was branched from #<A>, so after
squash-merging #<A>, use `git rebase --onto` to rebase #<B> cleanly.

## Steps

1. Poll CI for PR #<A> using Adaptive Polling Strategy from `ci--job-dependency-graph.md` § Adaptive Polling Strategy:
2. Merge PR #<A>: `gh pr merge <A> --squash --delete-branch`
3. Verify: `gh pr view <A> --json state -q '.state'` → "MERGED"
4. Check PR #<B> mergeability: `gh pr view <B> --json mergeable -q '.mergeable'`
5. If CONFLICTING, rebase #<B> onto updated main:
   a. `git fetch origin main`
   b. `git checkout <branch-B>`
   c. Identify commits to keep (only #<B>'s own commits, not #<A>'s):
      `git log --oneline origin/main..<branch-B>`
   d. Find the boundary (last commit from #<A>):
      The commit just before #<B>'s first unique commit.
   e. `git rebase --onto origin/main <boundary-commit> <branch-B>`
   f. `git push --force-with-lease origin <branch-B>`
6. Poll CI for PR #<B> using Adaptive Polling Strategy from `ci--job-dependency-graph.md` § Adaptive Polling Strategy:
7. Merge PR #<B>: `gh pr merge <B> --squash --delete-branch`
8. Verify: `gh pr view <B> --json state -q '.state'` → "MERGED"

## Git operations allowed (scoped)
- `git fetch origin main` — read-only sync
- `git checkout <branch-B>` — only the specific branch listed above
- `git rebase --onto origin/main <commit> <branch-B>` — targeted rebase
- `git push --force-with-lease origin <branch-B>` — only the rebased branch
- NEVER push to main directly

## Error handling
- If CI fails on either PR: stop, report which check failed and the details URL
- If rebase --onto has conflicts: abort rebase (`git rebase --abort`), report the conflicting files
- If merge fails: report the error, do NOT retry

## Return format
Report:
- PR #<A>: merged (yes/no), merge SHA
- PR #<B>: merged (yes/no), merge SHA
- Any errors encountered
```
