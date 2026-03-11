---
trigger: bot review trigger, bot review detection, bot review timing, bot re-review, CodeRabbit trigger, Codex trigger, Two-Tier Trigger Model, coderabbit detection, CodeRabbit completion, coderabbit polling, Polling Algorithm, rate limit recovery, rate limit wait time, rate limit parse, 429 threshold, eyes reaction delay, re-review decision, review re-trigger, @coderabbitai review, @codex review, trigger conditions
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

```bash
# CodeRabbit (always — every PR):
gh pr comment <PR> --body "@coderabbitai review"

# Codex (user instruction only):
gh pr comment <PR> --body "@codex review"
```

Agent triggers CodeRabbit in `pr-create` Step 5a and `review-fix` Step 5b.
Auto-review is OFF. Codex is triggered **only when the user explicitly
instructs** — the agent never triggers Codex autonomously.

### CR Review Budget

**Max 2 review requests per PR.** This includes the initial review and
at most 1 re-review. If the budget is exhausted, the agent proceeds
with the evidence already collected (existing review results + agent
verification). Rate-limit recovery re-triggers do NOT count against
the budget (the original request was not fulfilled).

## Detection

**Login patterns**: CodeRabbit = `coderabbit`, Codex = `chatgpt-codex-connector|codex|openai`.

### API Channels

| Channel | Endpoint | What it returns |
|---|---|---|
| Review | `pulls/<N>/reviews` | Review with state and body |
| Inline | `pulls/<N>/comments` | Line-level findings |
| PR comment | `issues/<N>/comments` | Walkthrough / clean bill / rate limit |

### Terminal States

| State | Detection |
|---|---|
| **COMPLETED** | Review with `submitted_at > trigger_time` and `body != ""` |
| **COMPLETED_CLEAN** | Codex only: thumbs-up on trigger comment |
| **COMPLETED_SILENT** | CR incremental review only: trigger acked, > 7 min elapsed, no review object, no inline comments, no rate limit, no new threads |
| **RATE_LIMITED** | PR comment contains "Rate limit exceeded" (after `trigger_time`) |
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
