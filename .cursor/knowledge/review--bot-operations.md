---
trigger: bot review trigger, bot review detection, bot review timing, bot re-review, CodeRabbit trigger, Codex trigger, Two-Tier Trigger Model, coderabbit detection, CodeRabbit completion, coderabbit polling, Polling Algorithm, rate limit recovery, rate limit wait time, rate limit parse, 429 threshold, eyes reaction delay, re-review decision, review re-trigger, @coderabbitai review, @codex review, trigger conditions, REVIEW_INVALIDATED, head commit changed, open source coderabbit yaml
---
# Bot Review Operations

Consolidated operational reference for AI code reviewers (CodeRabbit and
Codex). Covers trigger, detection, timing, rate limits, and re-review.

For the consensus model (disposition, resolve, agreement), see
`review--consensus-protocol.md`.

## Reviewers

| Role | Reviewer | When triggered | Strength |
|---|---|---|---|
| **Primary** | CodeRabbit (Pro/OSS) | Every PR (agent-triggered) | Walkthrough, tool integrations, incremental review |
| **Supplementary** | Codex Cloud | User instruction only | Cross-file logic, deep semantic understanding |

Both read `AGENTS.md` and apply its review guidelines.

## Trigger

- **CodeRabbit**: Agent-triggered on every PR (`pr-create` Step 5a,
  `review-fix` Step 5b). Auto-review is OFF.
- **Codex**: User instruction only — the agent never triggers
  Codex autonomously.

Trigger commands are in `pr-create.md` Step 5a/5b (not duplicated here).

### CR Review Budget

**SSOT (numeric cap)**: `max_reviews` on the `coderabbit` entry in
`docs/agent-control/review-bots.json`. `evidence-pull-request` surfaces it as
`reviews.bot_coderabbit.max_reviews`. Do not restate the number in other
artifacts — link or reference that field.

**Procedure**: Each agent-triggered `@coderabbitai review` cycle consumes
budget in the sense that `review_count` (from the PR review timeline) is
compared to `max_reviews` in merge-readiness logic (`pull-request-readiness.jq`,
loaded with the same `review-bots.json`). When exhausted, do not post further
`@coderabbitai review`; proceed with existing evidence plus human/agent
verification. Rate-limit recovery re-triggers do NOT count against the budget
(the original request was not fulfilled).

**FSM when exhausted** (CI green, `disposition` still `pending`, no unresolved
threads, no `rereview_response_pending`): required CodeRabbit is treated as
**done** if `bot_coderabbit.status == "NOT_TRIGGERED"` and
`review_count >= max_reviews` (`required_bot_done` in
`pull-request-readiness.jq`). Then `required_bot_rereview` is **not** added for
that row, so consensus can reach `review_consensus_complete` and
`pr_state_id == "ReviewDone"` when merge preconditions are otherwise satisfied.
See golden case `tc-pr-coderabbit-budget-exhausted.json`.

## Detection

Bot identities are defined in `docs/agent-control/review-bots.json`
(SSOT for bot configuration). The evidence script reads this config
to dynamically detect bots without hardcoded login patterns.

For the current login matchers, see `docs/agent-control/review-bots.json`.

### API Channels

| Channel | Endpoint | What it returns |
|---|---|---|
| Review | `pulls/<N>/reviews` | Review with state and body |
| Inline | `pulls/<N>/comments` | Line-level findings |
| PR comment | `issues/<N>/comments` | Walkthrough / clean bill / rate limit |

### Open-source: `.coderabbit.yaml` on the PR branch

On **open-source** repositories, CodeRabbit applies **only** the configuration from the **base branch** for an open PR. Changes to `.coderabbit.yaml` in the PR (for example `commit_status: true`) are ignored until they are merged. Expect UI warnings to that effect; do not assume PR-local YAML is active for the current review run.

### Voided review (head moved during bot run)

If the branch is **force-pushed or updated** while CodeRabbit is reviewing, CR may post a PR comment such as “Review failed” / “The head commit changed during the review from … to …”. That is **not** a completed review for the new head.

- **Evidence**: `make evidence-pull-request` sets `bot_coderabbit.status` to `REVIEW_INVALIDATED` when an issue comment from the bot matches `invalidate_review_pattern` in `review-bots.json` with `created_at` on or after `reviews.last_push_at` (same freshness rule as rate-limit comments).
- **Procedure**: Re-trigger `@coderabbitai review` after the push stabilizes. Do not treat a voided run as `bot_review_completed` or merge-ready on bot evidence alone.
- **Prevention**: Avoid pushing again while `BotReviewPending` unless you plan to re-trigger CR (or accept agent `pr-review` per FSM).

### Terminal States

When CodeRabbit `commit_status` is enabled (`.coderabbit.yaml`) and `review-bots.json` sets `commit_status_name`, `make evidence-pull-request` prefers the matching GitHub `statusCheckRollup` check over review/comment heuristics for `bot_coderabbit.status`. That check is excluded from PR `ci.status` so pending bot review does not block the CI-green signal. `REVIEW_INVALIDATED` (from issue comments) **overrides** commit-status/review-derived status when matched. `RATE_LIMITED` is not overridden by skip detection.

Per-bot `skip_patterns` and `skip_policy` in `review-bots.json` detect **issue comments from that bot** since `reviews.last_push_at` whose body matches a pattern (e.g. “Review skipped” / auto-review disabled on OSS). The first match sets `SKIPPED_CLEAN` or `SKIPPED_BLOCKED` and fills `skip_detected` / `skip_reason` / `skip_detected_at`. Skip detection runs after commit-status resolution and **overrides** `COMPLETED` when the comment shows the run was skipped — a `@coderabbitai` trigger line in the same thread is **not** a substitute for parsing this outcome.

| State | Detection |
|---|---|
| **COMPLETED** | Preferred: matching commit status `SUCCESS` on the head. Otherwise: review with `submitted_at` on or after the current head push (`reviews.last_push_at`; aligns with delegation `trigger_time` after a push) |
| **PENDING** | Matching commit status not yet `COMPLETED` on the head |
| **COMPLETED_CLEAN** | Codex only: thumbs-up on trigger comment |
| **COMPLETED_SILENT** | CR incremental review only: trigger acked, > 10 min elapsed, no review object, no inline comments, no rate limit, no new threads |
| **RATE_LIMITED** | Matching commit status `FAILURE` when present; else PR comment matches bot `rate_limit_pattern` with `created_at` on or after head push time (same cutoff as `reviews.last_push_at`; stale comments from before the push are ignored) |
| **REVIEW_INVALIDATED** | PR **issue** comment from the bot matches `invalidate_review_pattern` since head push (e.g. head commit changed mid-review) — overrides other signals for that bot |
| **SKIPPED_CLEAN** | PR **issue** comment from the bot matches `skip_patterns` with `skip_policy: "terminal_clean"` — treated as a completed required-bot outcome for merge consensus (no `required_bot_rereview` for that row) |
| **SKIPPED_BLOCKED** | Same as above with `skip_policy: "terminal_blocked"` — merge consensus fails; `auto_merge_readiness.blockers` includes `required_bot_skipped_blocked` (fix CodeRabbit settings / policy) |
| **TIMED_OUT** | 20 min elapsed, no completion signal |

**COMPLETED_SILENT**: When CR's incremental review finds no new issues,
it does not post a review object. The absence of output after sufficient
time IS the signal. This is distinct from TIMED_OUT (which uses the
20 min threshold).

Always use API checks — never infer from timing alone.

## Timing

| | CodeRabbit | Codex |
|---|---|---|
| Typical completion | 2–7 min | 1–7 min |
| Polling interval | 30 s | 30 s |
| Timeout | 20 min | 20 min |

## Optional-bot fallback ordering (v1)

When CodeRabbit recovery is exhausted, operators may manually invoke **user_only** reviewers listed in `docs/agent-control/review-bots.json`. Sort by `fallback_priority` ascending (lower runs first; `null` sorts last). **Agents do not** post these mentions in v1 — document the mention text for the user (see `delegation--review-wait.md` § Recovery waterfall).

**Claude Code** is registered as `claude_code` with `login_pattern` `^$` (matches no GitHub login) until a real bot username is confirmed — fallback is **documentation-only** until updated.

## Rate-Limit Recovery

1. Detect: PR comment from bot containing "Rate limit exceeded"
2. Parse wait time: `wait \*\*(\d+) minutes? and (\d+) seconds?\*\*`
   → `minutes * 60 + seconds + 30` (30s buffer)
3. Sleep, re-trigger same reviewer
4. Fetch the new trigger comment's `id` and `created_at`, then reset
   `trigger_time` and `trigger_id` to these fresh values before resuming
5. Second rate limit → treat as TIMED_OUT (max 1 recovery)

**Codex fallback**: None. Codex is triggered only by user instruction.

## Agreement Mechanics

How each bot expresses agreement after a disposition reply:

| Behavior | CodeRabbit | Codex |
|---|---|---|
| Reads disposition replies | **Yes** — checks referenced commit | **No** |
| Confirms fix | Replies with confirmation + **auto-resolves thread** | N/A (does not read replies) |
| Objects | Replies with objection, thread stays unresolved | N/A |
| Agreement via re-review | Also works (no new finding = agreement) | **Only method** (no new finding = implicit agreement) |
| Usage limit (permanent) | Not observed | Possible — "reached your Codex usage limits" (not recoverable) |

**Implication**: After posting a disposition reply, check thread state
first. If CodeRabbit already confirmed and auto-resolved, no re-review
is needed. For Codex, re-review is the only path to consensus.

## Re-review

Agent re-triggers CR after `review-fix` push, subject to the budget:

| Condition | CodeRabbit | Codex |
|---|---|---|
| Push to PR branch (budget remaining) | `@coderabbitai review` | — |
| Push to PR branch (budget exhausted) | No — use existing evidence | — |
| User instructs Codex re-review | — | `@codex review` |

All findings receive equal evaluation (P0/P1) regardless of source.
Deduplicate when both reviewers flag the same issue.

## Re-review signal telemetry (`evidence-pull-request`)

`make evidence-pull-request` exposes CodeRabbit re-review **detection** beyond the single latest timestamp:

| Field | Role |
|-------|------|
| `reviews.re_review_signal.latest_cr_trigger_created_at` | SSOT moment compared to bot pull reviews / commit-status completion |
| `reviews.re_review_signal.latest_cr_review_submitted_at_after_trigger` | Latest completion timestamp after the trigger among pull reviews, commit-status completion, and skip-pattern issue comments |
| `reviews.re_review_signal.latest_cr_skip_comment_at_after_trigger` | Timestamp of the latest `coderabbitai[bot]` issue comment after the trigger that matched `skip_patterns` (diagnostic; also folded into `latest_cr_review_submitted_at_after_trigger`) |
| `reviews.re_review_signal.trigger_comment_log` | Up to five most recent PR **issue** comments matching `@coderabbitai` + `review` (newest first), each `{created_at, id}` |

**Use `trigger_comment_log` when** the latest trigger time looks wrong (multiple rapid re-triggers, manual comment edits, or suspicion that delegation used a stale `trigger_id`). The log is **diagnostic only** — FSM and blockers still key off `latest_cr_trigger_created_at` and `cr_response_pending_after_latest_trigger`.

**Skip responses:** `cr_response_pending_after_latest_trigger` is `false` when a skip-pattern comment after the trigger is detected, or when `bot_coderabbit.status` is `SKIPPED_CLEAN` / `SKIPPED_BLOCKED`, so `@coderabbitai` + `review` trigger text alone cannot deadlock `BotReviewPending` if CodeRabbit replied with a skip notice.

**Truncation:** `reviews.review_threads_truncated` is `true` when GraphQL `reviewThreads(first:100)` has a next page. While true, treat `threads_unresolved` as **incomplete** for merge consensus; refresh after resolution or use `evidence-review-threads` for targeted enumeration when needed.

## Polling Algorithm

```text
INPUTS:
  trigger_time  — trigger comment created_at
  trigger_id    — trigger comment ID
  reviewer      — "coderabbit" | "codex"
  timeout       — 20 min

POLL (every 30s):
  1. Reviews: filter by login, submitted_at > trigger_time, body != ""
     → if any → COMPLETED
  2. Codex only: reactions on trigger_id, "+1" > 0 → COMPLETED_CLEAN
  3. Rate limit: PR comments from bot, created_at > trigger_time,
     body matches "Rate limit exceeded" → RATE_LIMITED
  4. elapsed > timeout → TIMED_OUT
```

Wait is delegated to background subagents via `delegation--review-wait.md`.

## Related

- `review--consensus-protocol.md` — disposition, resolve, consensus model
- `agent-safety.mdc` § Bot Review Enforcement
- `delegation--review-wait.md` — subagent wait template
- `.coderabbit.yaml` — CodeRabbit configuration
