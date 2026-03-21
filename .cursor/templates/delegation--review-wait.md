# Template: Review Wait (with optional CI monitoring)

Use after `pr-create` or `review-fix` when bot review has been triggered.
Optionally monitors CI in parallel. Replaces the former separate templates
for "CI + bot review" and "bot review only".

See `review--bot-operations.md` for detection, timing, and polling details.

```text
## Goal
Monitor bot reviews (and optionally CI) for PR #<N>. Report when all
triggered reviewers complete (or timeout).

## Inputs (provided by main agent)
- PR number: <N>
- Monitor CI: YES / NO
- CodeRabbit triggered: YES / NO
- CodeRabbit trigger_time: <ISO timestamp> (created_at of trigger comment)
- CodeRabbit trigger_id: <comment ID>
- Codex triggered: YES / NO
- Codex trigger_time: <ISO timestamp> (if triggered)
- Codex trigger_id: <comment ID> (if triggered)

**Critical**: `trigger_time` must be the exact `created_at` of the
trigger comment. Approximate timestamps cause false-negative detection.

## Steps

Poll using the algorithm from review--bot-operations.md § Polling Algorithm.

1. Poll in parallel (30s intervals, max 20 min elapsed):
   - CI (if Monitor CI = YES): `gh pr checks <N>`
   - CodeRabbit (if triggered):
     Reviews: `gh api repos/{owner}/{repo}/pulls/<N>/reviews --jq '[.[] | select(.user.login | test("coderabbit"; "i")) | select(.body != "") | select(.submitted_at > "<trigger_time>")] | length'`
     Rate limit: `gh api repos/{owner}/{repo}/issues/<N>/comments --jq '[.[] | select(.user.login | test("coderabbit"; "i")) | select(.created_at > "<trigger_time>") | select(.body | test("Rate limit exceeded"))] | length'`
   - Codex (if triggered):
     Reviews: `gh api repos/{owner}/{repo}/pulls/<N>/reviews --jq '[.[] | select(.user.login | test("chatgpt-codex-connector|codex|openai"; "i")) | select(.body != "") | select(.submitted_at > "<trigger_time>")] | length'`
     Rate limit: `gh api repos/{owner}/{repo}/issues/<N>/comments --jq '[.[] | select(.user.login | test("chatgpt-codex-connector|codex|openai"; "i")) | select(.created_at > "<trigger_time>") | select(.body | test("Rate limit exceeded"))] | length'`
     Clean bill: `gh api repos/{owner}/{repo}/issues/comments/<trigger_id> --jq '.reactions["+1"]'`

2. Terminal states (reviewers):
   - COMPLETED: review count > 0 (timestamp-filtered, non-empty body)
   - COMPLETED_CLEAN: Codex thumbs-up > 0 on trigger comment
   - COMPLETED_SILENT: CR only — trigger acked, > 10 min, no review/inline/rate-limit/new-threads
   - RATE_LIMITED: rate limit comment detected
   - REVIEW_INVALIDATED: PR issue comment from bot matches voided-review pattern since head push (e.g. head commit changed during review) — confirm via `make evidence-pull-request PR=<N>` → `reviews.bot_coderabbit.status`; then re-trigger `@coderabbitai review` and reset trigger metadata
   - TIMED_OUT: 20 min elapsed

   Terminal states (CI, if monitored):
   - PASSED: all checks pass
   - FAILED: any check fails
   - TIMEOUT: 20 min elapsed, checks still pending

3. IF RATE_LIMITED:
   - Parse wait time (regex: `wait \*\*(\d+) minutes? and (\d+) seconds?\*\*`)
   - Sleep for parsed_seconds (includes 30s buffer)
   - Re-trigger: `gh pr comment <N> --body "@coderabbitai review"` (or @codex)
   - Reset trigger_time/trigger_id, resume polling
   - Second RATE_LIMITED → TIMED_OUT (max 1 retry)

4. Report when CI (if monitored) and all reviewers reach terminal state.

## Prohibitions
- Do NOT run `git checkout`, `git switch`, `git branch`, or `git rebase`
- Do NOT run `gh pr merge`
- Do NOT modify any files
- Use only `gh` CLI commands and `sleep`

## Error handling
- CI check fails: report which check and details URL
- Reviewer times out: report TIMEOUT (pr-review proceeds without it)
- Rate limit recovery fails: report TIMED_OUT

## Return format
CI: PASSED / FAILED (<check-name> — <details-url>) / TIMEOUT / NOT_MONITORED
CODERABBIT: REVIEWED / SILENT_CLEAN / RATE_LIMIT_RECOVERED / TIMEOUT / NOT_TRIGGERED
CODEX: REVIEWED / CLEAN (👍) / RATE_LIMIT_RECOVERED / TIMEOUT / NOT_TRIGGERED
```
