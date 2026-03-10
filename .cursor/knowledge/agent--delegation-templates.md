---
trigger: CI-wait template, CI-wait only, merge template, batch auto-merge, dependent PR merge, delegation template, subagent prompt template, background subagent, Codex wait, CI Codex wait
---
# Subagent Delegation Templates

Reusable templates for delegating blocking operations to background subagents.

## Decision Flowchart

Before choosing a template, follow this decision tree:

```
Codex review requested?
├── Yes + CI also pending ──→ Template 4: CI + Codex Wait
├── Yes + CI already passed ──→ Template 5: Codex-Wait Only
└── No
    └── PR ready to merge?
        ├── No (CI monitoring only) ──→ Template 2: CI-Wait Only
        └── Yes
            ├── Single PR?
            │   ├── Yes ──→ `gh pr merge --auto --squash` (preferred, Deterministic)
            │   │          └── Auto-merge failed? ──→ Template 1: CI-Wait + Merge (Fallback)
            │   └── No (multiple PRs)
            │       ├── Independent PRs ──→ Batch Auto-Merge (set --auto on each)
            │       └── Dependent PRs (shared commits) ──→ Template 3: Dependent Chain
```

**Primary path**: For single PRs after `pr-review`, use `gh pr merge --auto --squash`
(see `pr-merge.md` § Auto-merge). This moves merge execution from Steering (agent
polls and merges) to Deterministic (GitHub enforces required checks and merges
automatically). Templates below are for fallback or multi-PR coordination only.

## Batch Auto-Merge (multiple independent PRs)

For multiple independent PRs that all have `pr-review` completed, set auto-merge
on each PR individually. No subagent delegation is needed:

```bash
gh pr merge <A> --auto --squash
gh pr merge <B> --auto --squash
gh pr merge <C> --auto --squash
```

GitHub merges each PR independently as its CI passes. If auto-merge fails on
any PR, fall back to Template 1 for that specific PR.

## Template 1: CI-Wait + Merge (Fallback)

**Use only when `gh pr merge --auto` fails** (e.g., token scope issue, API error).
For the normal case, use auto-merge directly.

**Prerequisite**: `pr-review` has completed and concluded "Mergeable". For CI
polling before review, use Template 2 (CI-Wait Only).

```
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

## Return format
Report: "MERGED: PR #<N> squash-merged at <sha>" or "FAILED: <reason>"
```

## Template 2: CI-Wait Only (No Merge)

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

## Template 4: CI + Codex Wait

Use after `pr-create` when the agent has triggered Codex review (`@codex review`)
and CI is also pending. Waits for both to complete.

See `codex--review-lifecycle.md` for Codex behavioral details (detection commands,
timing, state signals).

```
## Goal
Monitor CI and Codex Cloud Review for PR #<N>. Report when both complete.

## Steps

1. Poll in parallel (30s intervals, max 10 min elapsed):
   - CI: `gh pr checks <N>`
   - Codex reviews (findings): `gh api repos/{owner}/{repo}/pulls/<N>/reviews --jq '[.[] | select(.user.type == "Bot" or (.user.login | test("codex|openai"; "i")))] | length'`
   - Codex inline comments: `gh api repos/{owner}/{repo}/pulls/<N>/comments --jq '[.[] | select(.user.type == "Bot" or (.user.login | test("codex|openai"; "i")))] | length'`
   - Codex PR comment (no-findings): `gh api repos/{owner}/{repo}/issues/<N>/comments --jq '[.[] | select(.user.type == "Bot" or (.user.login | test("codex|openai"; "i")))] | length'`

2. CI is done when: all checks pass, or any check fails.
3. Codex is done when: bot output in ANY channel > 0 (reviews, inline comments, or PR comments), or 7 min timeout.
4. If bot output body contains "usage limits", report RATE_LIMITED.
5. When both are done, report final status.

## Prohibitions
- Do NOT run `git checkout`, `git switch`, `git branch`, or `git rebase`
- Do NOT run `gh pr merge`
- Do NOT modify any files
- Use only `gh` CLI commands and `sleep`

## Error handling
- If a CI check fails: report which check failed and the details URL
- If Codex times out: report TIMEOUT (not an error — pr-review proceeds without Codex)

## Return format
CI: PASSED / FAILED (<check-name> — <details-url>)
CODEX: REVIEWED (<N> inline comments) / TIMEOUT / RATE_LIMITED
```

## Template 5: Codex-Wait Only

Use after `review-fix` when the agent has triggered Codex re-review
(`@codex review`) but CI has already passed or is being monitored separately.

```
## Goal
Monitor Codex Cloud Review for PR #<N> and report when complete.

## Steps
1. Poll (30s intervals, max 7 min elapsed):
   - Codex reviews: `gh api repos/{owner}/{repo}/pulls/<N>/reviews --jq '[.[] | select(.user.type == "Bot" or (.user.login | test("codex|openai"; "i")))] | length'`
   - Codex inline comments: `gh api repos/{owner}/{repo}/pulls/<N>/comments --jq '[.[] | select(.user.type == "Bot" or (.user.login | test("codex|openai"; "i")))] | length'`
   - Codex PR comment: `gh api repos/{owner}/{repo}/issues/<N>/comments --jq '[.[] | select(.user.type == "Bot" or (.user.login | test("codex|openai"; "i")))] | length'`
2. Done when bot output in ANY channel > 0, or timeout.
3. If bot output body contains "usage limits", report RATE_LIMITED.

## Prohibitions
- Do NOT run `git checkout`, `git switch`, `git branch`, or `git rebase`
- Do NOT run `gh pr merge`
- Do NOT modify any files

## Return format
CODEX: REVIEWED (<N> inline comments) / TIMEOUT / RATE_LIMITED
```

## Template 3: Dependent PR Merge Chain (rebase-enabled)

```
## Goal
Merge PRs #<A> and #<B> sequentially. #<B> was branched from #<A>, so after
squash-merging #<A>, use `git rebase --onto` to rebase #<B> cleanly.

## Steps

1. Poll CI for PR #<A> using Adaptive Polling Strategy from `ci--job-dependency-graph.md` § Adaptive Polling Strategy:
2. Merge PR #<A>: `gh pr merge <A> --squash`
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
7. Merge PR #<B>: `gh pr merge <B> --squash`
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
