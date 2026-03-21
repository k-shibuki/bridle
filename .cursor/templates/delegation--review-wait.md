# Template: Review Wait (with optional CI monitoring)

Use after `pr-create` or `review-fix` when bot review has been triggered.
Optionally monitors CI in parallel. Replaces the former separate templates
for "CI + bot review" and "bot review only".

See `review--bot-operations.md` for detection, timing, and polling details.

## Cursor Task invocation

- **Concurrent waits (multiple PRs)**: set `run_in_background: true` on the Task call.
- **Single PR**: use a **foreground** Tier 1 subagent by default (omit `run_in_background`) per `subagent-policy.mdc` and `next.md`.

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

3. IF RATE_LIMITED (first occurrence for this reviewer in this delegated wait):
   - Parse wait time (regex: `wait \*\*(\d+) minutes? and (\d+) seconds?\*\*`)
   - Sleep for parsed_seconds (includes 30s buffer)
   - Re-trigger **the same** bot only: CodeRabbit → `gh pr comment <N> --body "@coderabbitai review"`; Codex only if this wait cycle was started from an explicit user Codex trigger (same pattern as Step 1 inputs)
   - Reset trigger_time/trigger_id from the new trigger comment, resume polling

3b. Recovery waterfall (v1 — after **second** RATE_LIMITED or **TIMED_OUT** for the same reviewer, or if Step 3 retry is not applicable):
   - **Do not** post `@codex`, `@claude`, or other `user_only` bots from the subagent. Agents never auto-invoke optional bots in v1 (design freeze 2026-03-21; parent #271 / child #274).
   - Read `docs/agent-control/review-bots.json`: list optional bots (`required: false`, `trigger: "user_only"`) sorted by `fallback_priority` ascending (nulls last). For each, tell the **operator** the exact mention/runbook step so they may invoke a review manually if they choose.
   - If the operator does not invoke an optional bot, or invoked bots do not produce a review before the outer timeout, treat the reviewer line as exhausted for this cycle.

4. When all automated reviewer paths are exhausted and CodeRabbit (required) is still not in a Reviewed-tier outcome, the subagent return must include **`REVIEW_NEEDED`**: the main agent shall run `pr-review` using `make evidence-pull-request PR=<N>` (FSM: `bot_review_failed` or incomplete required bot → `ReadyForReview` path).

5. Report when CI (if monitored) and all reviewers reach terminal state (or `REVIEW_NEEDED` has been emitted for the required reviewer per Step 4).

## Prohibitions
- Do NOT run `git checkout`, `git switch`, `git branch`, or `git rebase`
- Do NOT run `gh pr merge`
- Do NOT modify any files
- Use only `gh` CLI commands and `sleep`

## Error handling
- CI check fails: report which check and details URL
- Reviewer times out: report TIMEOUT; if required bot still lacks a Reviewed-tier outcome, include `REVIEW_NEEDED` per Step 4
- Rate limit recovery exhausted: report terminal state and optional-bot instructions from Step 3b; include `REVIEW_NEEDED` when the required reviewer never reached Reviewed tier

## Return format
CI: PASSED / FAILED (<check-name> — <details-url>) / TIMEOUT / NOT_MONITORED
CODERABBIT: REVIEWED / SILENT_CLEAN / RATE_LIMIT_RECOVERED / TIMEOUT / NOT_TRIGGERED / REVIEW_NEEDED
CODEX: REVIEWED / CLEAN (👍) / RATE_LIMIT_RECOVERED / TIMEOUT / NOT_TRIGGERED
CLAUDE_CODE: NOT_TRIGGERED / USER_PATH_ONLY (v1 — registry login_pattern placeholder; no agent auto-trigger)
Aggregate: include `REVIEW_NEEDED` when Step 4 applies so the main agent runs `pr-review`.
```
