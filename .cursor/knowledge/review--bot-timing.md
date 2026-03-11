---
trigger: bot review timing, rate limit recovery, rate limit wait time, rate limit re-trigger, rate limit parse, 429 threshold, eyes reaction delay
---
# Bot Review Timing

Timing constants, rate-limit detection, and recovery mechanics for bot
reviewers.

## Timing

| | CodeRabbit | Codex |
|---|---|---|
| Typical completion | 2–7 min | 1–7 min |
| Eyes/Ack delay | 0s–5min+ | N/A |
| Polling interval | 30 s | 30 s |
| Timeout | 20 min | 20 min |

**Eyes/Ack delay**: Up to 5min+ observed (PR #187 trigger 3). These
signals are unreliable for early termination — only timeout is definitive.

## CodeRabbit Pro/OSS Rate Limits

OSS repositories get Pro features free. Rate limits are generous:

| Resource | Limit |
|----------|-------|
| Files per hour | 200 |
| Back-to-back PR reviews | 3, then 4 reviews/hour |
| Chat messages | 25 back-to-back, then 50/hour |

## Rate-Limit Detection and Recovery Pattern

This section documents the **mechanics** of rate-limit detection and
recovery. The **policy** (recover vs skip) is in `subagent-policy.mdc`
§ Rate-Limit Recovery Policy.

### Detection

**CodeRabbit**: Posts a PR comment (not a review) when rate-limited. Detect via:

```bash
gh api repos/{owner}/{repo}/issues/<N>/comments \
  --jq '[.[] | select(.user.login | test("coderabbit"; "i"))
        | select(.created_at > "<trigger_time>")
        | select(.body | test("Rate limit exceeded"))
        | {id, created_at, body}]'
```

**Codex**: Rate-limit behavior has not been observed. If Codex implements
rate limiting in the future, detection should follow the same pattern.

### Wait Time Parsing

The rate-limit comment contains an embedded wait time in bold:

> Please wait **4 minutes and 43 seconds** before requesting another review.

Extract with regex:

```regex
wait \*\*(\d+) minutes? and (\d+) seconds?\*\*
```

Convert to seconds: `minutes * 60 + seconds + 30` (30s safety buffer included).

### Recovery Flow

1. Detect RATE_LIMITED via PR comment (see Detection above)
2. Parse wait time from comment body (includes 30s buffer per formula above)
3. Sleep for `parsed_seconds`
4. Re-trigger: `gh pr comment <N> --body "@coderabbitai review"`
5. Reset `trigger_time` and `trigger_id` to the new comment's values,
   reset state to TRIGGERED, resume polling
6. If a second RATE_LIMITED occurs: stop, report as TIMED_OUT

Maximum 1 recovery attempt per reviewer per PR.

## Codex Fallback on CodeRabbit TIMED_OUT

When CodeRabbit reaches TIMED_OUT (including after a failed rate-limit recovery), the agent should consider triggering Codex as a fallback reviewer — but only if the change type warrants it.

| Change type | Codex fallback? | Rationale |
|---|---|---|
| R code, schemas, security, ADRs | **Yes** — trigger `@codex review` | High-risk changes need at least one bot review |
| CI config, shell scripts, workflow, docs | No | Low-risk; proceed to `pr-review` with Cursor self-review only |

The fallback trigger follows the same flow as the initial Codex trigger
(`review--bot-trigger.md` § Two-Tier Trigger Model) and uses the same
monitoring template (`delegation--ci-bot-review-wait.md` or
`delegation--bot-review-wait.md`).

## Related

- `review--bot-trigger.md` — trigger rules and two-tier model
- `review--bot-detection.md` — output detection, state machine, polling
- `review--bot-re-review.md` — re-review after review-fix
