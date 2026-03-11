---
trigger: CI-wait template, CI-wait only, merge template, batch auto-merge, dependent PR merge, delegation template, subagent prompt template, background subagent, Codex wait, CI Codex wait
---
# Subagent Delegation Templates

Reusable templates for delegating blocking operations to background subagents.

## Decision Flowchart

Before choosing a template, follow this decision tree:

```text
Bot review triggered?
├── Yes + CI also pending ──→ Template 4: CI + Bot Review Wait
├── Yes + CI already passed ──→ Template 5: Bot Review Wait Only
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

## Return format
Report: "MERGED: PR #<N> squash-merged at <sha>" or "FAILED: <reason>"
```

## Template 2: CI-Wait Only (No Merge)

```text
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

## Template 4: CI + Bot Review Wait

Use after `pr-create` when bot review has been triggered and CI is also
pending. Polls all triggered reviewers in parallel — no fallback chain.

The main agent tells the subagent which reviewers were triggered
(CodeRabbit always, agent-triggered in pr-create/review-fix; Codex only for complex changes).
See `review--bot-lifecycle.md` for the two-tier trigger model.

```text
## Goal
Monitor CI and bot reviews for PR #<N>. Report when both CI and all
triggered bot reviews complete (or timeout).

## Inputs (provided by main agent)
- PR number: <N>
- CodeRabbit triggered: YES / NO
- CodeRabbit trigger_time: <ISO timestamp> (created_at of trigger comment)
- CodeRabbit trigger_id: <comment ID>
- Codex triggered: YES / NO
- Codex trigger_time: <ISO timestamp> (if triggered)
- Codex trigger_id: <comment ID> (if triggered)

**Critical**: `trigger_time` must be the exact `created_at` of the
trigger comment, not an approximation. The main agent must capture
this at trigger time and pass it to the subagent. Approximate
timestamps cause false-negative state detection (ack from previous
trigger mistaken for current trigger, or current trigger's ack missed).

## Steps

Use the polling algorithm from review--bot-lifecycle.md § Polling Algorithm.
Key principle: detect completion by TIMESTAMP, not by count.

1. Poll in parallel (30s intervals, max 10 min elapsed):
   - CI: `gh pr checks <N>`
   - CodeRabbit (if triggered):
     - Reviews (timestamp-filtered, empty body excluded):
       `gh api repos/{owner}/{repo}/pulls/<N>/reviews --jq '[.[] | select(.user.login | test("coderabbit"; "i")) | select(.body != "") | select(.submitted_at > "<trigger_time>")] | length'`
     - Early signals (informational, do not terminate polling):
       Eyes: `gh api repos/{owner}/{repo}/issues/comments/<trigger_id> --jq '.reactions.eyes'`
       Ack: `gh api repos/{owner}/{repo}/issues/<N>/comments --jq '[.[] | select(.user.login | test("coderabbit"; "i")) | select(.created_at > "<trigger_time>") | select(.body | test("Review triggered"))] | length'`
   - Codex (if triggered):
     - Reviews (timestamp-filtered):
       `gh api repos/{owner}/{repo}/pulls/<N>/reviews --jq '[.[] | select(.user.login | test("chatgpt-codex-connector|codex|openai"; "i")) | select(.body != "") | select(.submitted_at > "<trigger_time>")] | length'`
     - Clean bill (thumbs-up on trigger):
       `gh api repos/{owner}/{repo}/issues/comments/<trigger_id> --jq '.reactions["+1"]'`

2. CI is done when: all checks pass, or any check fails.
3. A reviewer is done when:
   - COMPLETED: review count > 0 (timestamp-filtered, non-empty body)
   - COMPLETED_CLEAN: Codex thumbs-up > 0 on trigger comment
   - RATE_LIMITED: PR comment from reviewer contains "Rate limit exceeded"
   - TIMED_OUT: 7 min elapsed with no completion signal
3a. IF reviewer reports RATE_LIMITED (per `subagent-policy.mdc` § Rate-Limit Recovery Policy):
   - Parse wait time from the rate-limit comment (see `review--bot-lifecycle.md` § Rate-Limit Detection and Recovery Pattern; 30s buffer is already included in the parsed value)
   - Sleep for parsed_seconds
   - Re-trigger the same reviewer that was rate-limited:
     - CodeRabbit: `gh pr comment <N> --body "@coderabbitai review"`
     - Codex: `gh pr comment <N> --body "@codex review"`
   - Reset both trigger_time and trigger_id to the new comment's created_at and ID
   - Resume polling from Step 1
   - IF second RATE_LIMITED: treat as TIMED_OUT (max 1 retry)
4. Report final status when CI and all triggered reviewers are done.

## Prohibitions
- Do NOT run `git checkout`, `git switch`, `git branch`, or `git rebase`
- Do NOT run `gh pr merge`
- Do NOT modify any files
- Use only `gh` CLI commands and `sleep`

## Error handling
- If a CI check fails: report which check failed and the details URL
- If a reviewer times out: report TIMEOUT (not an error — pr-review proceeds without that reviewer)
- If a reviewer is rate-limited: attempt recovery per Step 3a. If recovery also fails, report TIMED_OUT.

## Return format
CI: PASSED / FAILED (<check-name> — <details-url>)
CODERABBIT: REVIEWED (<N> inline comments) / RATE_LIMIT_RECOVERED (waited Xm Ys, then reviewed — <N> comments) / TIMEOUT / NOT_TRIGGERED
CODEX: REVIEWED (<N> inline comments) / CLEAN (👍) / RATE_LIMIT_RECOVERED (waited Xm Ys, then reviewed — <N> comments) / TIMEOUT / NOT_TRIGGERED
```

## Template 5: Bot Review Wait Only

Use after `review-fix` when the agent has re-triggered bot review but
CI has already passed or is being monitored separately. Polls all
triggered reviewers in parallel.

See `review--bot-lifecycle.md` for re-review trigger conditions.

```text
## Goal
Monitor bot reviews for PR #<N> and report when complete.

## Inputs (provided by main agent)
- PR number: <N>
- CodeRabbit triggered: YES / NO
- CodeRabbit trigger_time: <ISO timestamp> (created_at of trigger comment)
- CodeRabbit trigger_id: <comment ID>
- Codex triggered: YES / NO
- Codex trigger_time: <ISO timestamp> (if triggered)
- Codex trigger_id: <comment ID> (if triggered)

**Critical**: `trigger_time` must be the exact `created_at` of the
trigger comment, not an approximation. The main agent must capture
this at trigger time and pass it to the subagent. Approximate
timestamps cause false-negative state detection (ack from previous
trigger mistaken for current trigger, or current trigger's ack missed).

## Steps

Use the polling algorithm from review--bot-lifecycle.md § Polling Algorithm.
Key principle: detect completion by TIMESTAMP, not by count.

1. Poll triggered reviewers in parallel (30s intervals, max 7 min elapsed):
   - CodeRabbit (if triggered):
     - Reviews (timestamp-filtered, empty body excluded):
       `gh api repos/{owner}/{repo}/pulls/<N>/reviews --jq '[.[] | select(.user.login | test("coderabbit"; "i")) | select(.body != "") | select(.submitted_at > "<trigger_time>")] | length'`
   - Codex (if triggered):
     - Reviews (timestamp-filtered):
       `gh api repos/{owner}/{repo}/pulls/<N>/reviews --jq '[.[] | select(.user.login | test("chatgpt-codex-connector|codex|openai"; "i")) | select(.body != "") | select(.submitted_at > "<trigger_time>")] | length'`
     - Clean bill (thumbs-up on trigger):
       `gh api repos/{owner}/{repo}/issues/comments/<trigger_id> --jq '.reactions["+1"]'`
2. A reviewer is done when:
   - COMPLETED: review count > 0 (timestamp-filtered, non-empty body)
   - COMPLETED_CLEAN: Codex thumbs-up > 0 on trigger comment
   - RATE_LIMITED: PR comment from reviewer contains "Rate limit exceeded"
   - TIMED_OUT: 7 min elapsed with no completion signal
2a. IF reviewer reports RATE_LIMITED (per `subagent-policy.mdc` § Rate-Limit Recovery Policy):
   - Parse wait time from the rate-limit comment (see `review--bot-lifecycle.md` § Rate-Limit Detection and Recovery Pattern; 30s buffer is already included in the parsed value)
   - Sleep for parsed_seconds
   - Re-trigger the same reviewer that was rate-limited:
     - CodeRabbit: `gh pr comment <N> --body "@coderabbitai review"`
     - Codex: `gh pr comment <N> --body "@codex review"`
   - Reset both trigger_time and trigger_id to the new comment's created_at and ID
   - Resume polling from Step 1
   - IF second RATE_LIMITED: treat as TIMED_OUT (max 1 retry)
3. Report final status when all triggered reviewers are done.

## Prohibitions
- Do NOT run `git checkout`, `git switch`, `git branch`, or `git rebase`
- Do NOT run `gh pr merge`
- Do NOT modify any files

## Return format
CODERABBIT: REVIEWED (<N> inline comments) / RATE_LIMIT_RECOVERED (waited Xm Ys, then reviewed — <N> comments) / TIMEOUT / NOT_TRIGGERED
CODEX: REVIEWED (<N> inline comments) / CLEAN (👍) / RATE_LIMIT_RECOVERED (waited Xm Ys, then reviewed — <N> comments) / TIMEOUT / NOT_TRIGGERED
```

## Template 3: Dependent PR Merge Chain (rebase-enabled)

```text
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
   g. Verify push reached remote:
      `git ls-remote origin <branch-B> | awk '{print $1}'` must equal `git rev-parse HEAD`
      If mismatch, see Error handling § force-with-lease rejected.
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
- If `git push --force-with-lease` is rejected:
  1. `git fetch origin` to sync tracking refs
  2. Compare remote SHA (`git ls-remote origin <branch-B>`) with local `HEAD` (`git rev-parse HEAD`)
  3. If SHAs match (prior push already succeeded): no further action needed
  4. If SHAs differ: retry `git push --force-with-lease` (fetch updated the lease baseline)
  5. If retry also fails: abort, report the conflict (see `git--quick-recovery.md`)

## Return format
Report:
- PR #<A>: merged (yes/no), merge SHA
- PR #<B>: merged (yes/no), merge SHA
- Branch #<B> post-rebase HEAD: <sha> (from `git rev-parse HEAD`)
- Push verification: remote SHA matches local HEAD (yes/no)
- Any errors encountered
```
