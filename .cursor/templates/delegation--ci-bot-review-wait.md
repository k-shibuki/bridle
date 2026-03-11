# Template: CI + Bot Review Wait

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

1. Poll in parallel (30s intervals, max 20 min elapsed):
   - CI: `gh pr checks <N>`
   - CodeRabbit (if triggered):
     - Reviews (timestamp-filtered, empty body excluded):
       `gh api repos/{owner}/{repo}/pulls/<N>/reviews --jq '[.[] | select(.user.login | test("coderabbit"; "i")) | select(.body != "") | select(.submitted_at > "<trigger_time>")] | length'`
     - Rate limit comments:
       `gh api repos/{owner}/{repo}/issues/<N>/comments --jq '[.[] | select(.user.login | test("coderabbit"; "i")) | select(.created_at > "<trigger_time>") | select(.body | test("Rate limit exceeded"))] | length'`
     - Early signals (informational, do not terminate polling):
       Eyes: `gh api repos/{owner}/{repo}/issues/comments/<trigger_id> --jq '.reactions.eyes'`
       Ack: `gh api repos/{owner}/{repo}/issues/<N>/comments --jq '[.[] | select(.user.login | test("coderabbit"; "i")) | select(.created_at > "<trigger_time>") | select(.body | test("Review triggered"))] | length'`
   - Codex (if triggered):
     - Reviews (timestamp-filtered):
       `gh api repos/{owner}/{repo}/pulls/<N>/reviews --jq '[.[] | select(.user.login | test("chatgpt-codex-connector|codex|openai"; "i")) | select(.body != "") | select(.submitted_at > "<trigger_time>")] | length'`
     - Rate limit comments:
       `gh api repos/{owner}/{repo}/issues/<N>/comments --jq '[.[] | select(.user.login | test("chatgpt-codex-connector|codex|openai"; "i")) | select(.created_at > "<trigger_time>") | select(.body | test("Rate limit exceeded"))] | length'`
     - Clean bill (thumbs-up on trigger):
       `gh api repos/{owner}/{repo}/issues/comments/<trigger_id> --jq '.reactions["+1"]'`

2. CI is done when: all checks pass, or any check fails.
3. A reviewer is done when:
   - COMPLETED: review count > 0 (timestamp-filtered, non-empty body)
   - COMPLETED_CLEAN: Codex thumbs-up > 0 on trigger comment
   - RATE_LIMITED: rate limit comment count > 0 (timestamp-filtered)
   - TIMED_OUT: 20 min elapsed with no completion signal
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
