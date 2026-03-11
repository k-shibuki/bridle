# Template: Bot Review Wait Only

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

1. Poll triggered reviewers in parallel (30s intervals, max 20 min elapsed):
   - CodeRabbit (if triggered):
     - Reviews (timestamp-filtered, empty body excluded):
       `gh api repos/{owner}/{repo}/pulls/<N>/reviews --jq '[.[] | select(.user.login | test("coderabbit"; "i")) | select(.body != "") | select(.submitted_at > "<trigger_time>")] | length'`
     - Rate limit comments:
       `gh api repos/{owner}/{repo}/issues/<N>/comments --jq '[.[] | select(.user.login | test("coderabbit"; "i")) | select(.created_at > "<trigger_time>") | select(.body | test("Rate limit exceeded"))] | length'`
   - Codex (if triggered):
     - Reviews (timestamp-filtered):
       `gh api repos/{owner}/{repo}/pulls/<N>/reviews --jq '[.[] | select(.user.login | test("chatgpt-codex-connector|codex|openai"; "i")) | select(.body != "") | select(.submitted_at > "<trigger_time>")] | length'`
     - Rate limit comments:
       `gh api repos/{owner}/{repo}/issues/<N>/comments --jq '[.[] | select(.user.login | test("chatgpt-codex-connector|codex|openai"; "i")) | select(.created_at > "<trigger_time>") | select(.body | test("Rate limit exceeded"))] | length'`
     - Clean bill (thumbs-up on trigger):
       `gh api repos/{owner}/{repo}/issues/comments/<trigger_id> --jq '.reactions["+1"]'`
2. A reviewer is done when:
   - COMPLETED: review count > 0 (timestamp-filtered, non-empty body)
   - COMPLETED_CLEAN: Codex thumbs-up > 0 on trigger comment
   - RATE_LIMITED: rate limit comment count > 0 (timestamp-filtered)
   - TIMED_OUT: 20 min elapsed with no completion signal
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
