---
trigger: bot review, Codex review, Codex trigger, @codex review, CodeRabbit, @coderabbitai review, eyes reaction, Codex lifecycle, Codex re-review, Codex rate limit, CodeRabbit rate limit, Codex wait, Codex Cloud Review, review fallback, coderabbit fallback, supplementary review, coderabbit detection, CodeRabbit completion, Review triggered, coderabbit in progress, coderabbit done, coderabbit polling, review ack vs completion, bot state machine, eyes reaction delay, empty body review, rate limit recovery, rate limit wait time, rate limit re-trigger, rate limit parse
---
# Bot Review Lifecycle

Single source of truth for AI code review behavior on PRs. Covers
CodeRabbit (primary) and Codex Cloud (supplementary). All commands
that interact with bot reviewers (`pr-create`, `pr-review`, `review-fix`,
`next`) reference this atom instead of embedding behavioral assumptions.

## Reviewers

| Role | Reviewer | When triggered | Strength |
|------|----------|---------------|----------|
| **Primary** | CodeRabbit (Pro/OSS) | All PRs (agent-triggered) | Walkthrough, tool integrations (shellcheck, yamllint), AGENTS.md auto-detect, no rate limit concern |
| **Supplementary** | Codex Cloud | Complex PRs only | Cross-file logic consistency, deep semantic understanding |

Both reviewers read `AGENTS.md` and apply its review guidelines
(severity policy, S7 type safety, test quality). CodeRabbit additionally
uses `knowledge_base.code_guidelines.enabled: true` to detect the file.

## Trigger

**CodeRabbit**: Agent triggers `@coderabbitai review` on every PR in `pr-create`
Step 5a and `review-fix` Step 5b. Auto-review is OFF (requires paid seat).

```bash
# CodeRabbit (always — every PR):
gh pr comment <PR> --body "@coderabbitai review"
```

**Codex**: Triggered **manually** via PR comment for complex changes only.

```bash
# Codex (only for complex changes — R code, schemas, security, ADRs):
gh pr comment <PR> --body "@codex review"
```

Agent triggers CodeRabbit in:
- `pr-create` Step 5a (after PR creation)
- `review-fix` Step 5b (after fix push)

Events that do **NOT** trigger Codex:
- PR open / draft → ready (must be triggered manually)
- Push / synchronize
- Rebase, label changes, PR body edits

## Two-Tier Trigger Model

Agent triggers CodeRabbit on **every PR** (Procedural — agent always triggers).
Agent decides whether to also trigger Codex (Steering — conditional).

| Change type | CodeRabbit | Codex | Rationale |
|-------------|-----------|-------|-----------|
| R code changes | Yes (agent) | **Yes** | Cross-file S7 class logic, NULL traps |
| Schema changes (`docs/schemas/`) | Yes (agent) | **Yes** | Schema-class consistency |
| Security-related changes | Yes (agent) | **Yes** | High risk, needs deep review |
| ADRs (`docs/adr/`) | Yes (agent) | **Yes** | Architecture-code alignment |
| CI config (`.github/workflows/`) | Yes (agent) | No | Breakage risk; yamllint covers syntax |
| Shell scripts (`tools/`) | Yes (agent) | No | shellcheck covers syntax |
| Workflow files (`.cursor/`) | Yes (agent) | No | Cross-reference consistency |
| Docs only (`.md`, non-ADR) | Yes (agent) | No | Low risk but still reviewed |

**Rate limit handling**: See `subagent-policy.mdc` § Rate-Limit Recovery Policy for the decision (recover vs skip). This section documents the detection pattern and recovery mechanics below (§ Rate-Limit Detection and Recovery Pattern).

## Output Detection

Both reviewers produce output through three API channels:

| Channel | API endpoint | CodeRabbit | Codex |
|---------|-------------|------------|-------|
| **Review** | `pulls/<N>/reviews` | Review with state | Summary + state: COMMENTED |
| **Inline comments** | `pulls/<N>/comments` | Line-level findings | Line-level findings (P0/P1 badges) |
| **PR comment** | `issues/<N>/comments` | Walkthrough summary | "Didn't find any major issues" (clean bill) |

### CodeRabbit detection

Bot login pattern: `coderabbit`.

```bash
# Reviews (filter empty body to exclude bot-to-bot reply artifacts)
gh api repos/{owner}/{repo}/pulls/<N>/reviews \
  --jq '[.[] | select(.user.login | test("coderabbit"; "i")) | select(.body != "") | {id, state, body, submitted_at}]'

# Inline comments
gh api repos/{owner}/{repo}/pulls/<N>/comments \
  --jq '[.[] | select(.user.login | test("coderabbit"; "i")) | {id, path, line: (.line // .original_line), body, created_at}]'

# Walkthrough / summary
gh api repos/{owner}/{repo}/issues/<N>/comments \
  --jq '[.[] | select(.user.login | test("coderabbit"; "i")) | {id, body, created_at}]'
```

### Codex detection

Bot login pattern: `chatgpt-codex-connector|codex|openai`.
Observed login: `chatgpt-codex-connector[bot]`. The broader pattern
provides backward compatibility if the login changes.

```bash
# Reviews (filter empty body to exclude bot-to-bot reply artifacts)
gh api repos/{owner}/{repo}/pulls/<N>/reviews \
  --jq '[.[] | select(.user.login | test("chatgpt-codex-connector|codex|openai"; "i")) | select(.body != "") | {id, state, body, submitted_at}]'

# Inline comments
gh api repos/{owner}/{repo}/pulls/<N>/comments \
  --jq '[.[] | select(.user.login | test("chatgpt-codex-connector|codex|openai"; "i")) | {id, path, line: (.line // .original_line), body, created_at}]'

# PR comments
gh api repos/{owner}/{repo}/issues/<N>/comments \
  --jq '[.[] | select(.user.login | test("chatgpt-codex-connector|codex|openai"; "i")) | {id, body, created_at}]'
```

## State Detection

| State | Detection | Applies to |
|-------|-----------|------------|
| **TRIGGERED** | Agent posted trigger comment | Both |
| **ACKNOWLEDGED** | Eyes reaction on trigger comment | CodeRabbit only |
| **ACCEPTED** | "Review triggered" ack comment after trigger time | CodeRabbit only |
| **COMPLETED** | Review entry with `submitted_at > trigger_time` AND `body != ""` | Both |
| **COMPLETED_CLEAN** | Thumbs-up on trigger comment (no findings) | Codex only |
| **RATE_LIMITED** | PR comment body contains "Rate limit exceeded" with embedded wait time (see § Rate-Limit Detection) | Both |
| **TIMED_OUT** | Timeout elapsed, no completion signal | Both |

**Rule**: Always use API checks to determine state. Do not infer state
from timing, absence of activity, or activity on other PRs.

**Anti-pattern — premature timeout**: Classifying a bot as TIMED_OUT
before the 20-min threshold has elapsed is prohibited. ACKNOWLEDGED and
ACCEPTED are intermediate states meaning the bot is actively processing.
The agent must continue polling (30s intervals) until a terminal state
is reached: COMPLETED, COMPLETED_CLEAN, RATE_LIMITED, or TIMED_OUT
(20 min elapsed). "Not responding after a brief wait" is not TIMED_OUT.

**Trigger time tracking**: Each trigger creates a new `trigger_time`
(the `created_at` of the trigger comment). All subsequent state
detection (ack, review, rate-limit) MUST filter by this specific
`trigger_time`. When a reviewer is re-triggered (e.g., after
review-fix), the old `trigger_time` is invalidated — acks and reviews
from the previous trigger are not evidence of the new trigger's state.

Common mistake: polling with an approximate trigger time (e.g., "around
05:15") instead of the exact `created_at` of the trigger comment. Always
capture the trigger comment ID and timestamp at trigger time:

```bash
# At trigger time, capture exact timestamp
COMMENT_URL=$(gh pr comment <N> --body "@coderabbitai review" 2>&1)
# Extract comment ID from the URL, then query created_at
trigger_time=$(gh api repos/{owner}/{repo}/issues/comments/<id> \
  --jq '.created_at')
```

**Critical**: CodeRabbit's "Review triggered" ack is NOT completion —
it is an intermediate signal (ACCEPTED). See § State Machine below.

## State Machine

### CodeRabbit (4 states + timeout)

```text
TRIGGERED ──[eyes on trigger]──→ ACKNOWLEDGED
TRIGGERED ──[review, body!="", submitted_at > t]──→ COMPLETED
ACKNOWLEDGED ──[ack "Review triggered"]──→ ACCEPTED
ACKNOWLEDGED ──[review, body!="", submitted_at > t]──→ COMPLETED
ACCEPTED ──[review, body!="", submitted_at > t]──→ COMPLETED
any state ──[timeout elapsed]──→ TIMED_OUT
any state ──[rate limit comment detected]──→ RATE_LIMITED
RATE_LIMITED ──[sleep wait_time + 30s, re-trigger]──→ TRIGGERED (retry)
RATE_LIMITED ──[second rate limit]──→ TIMED_OUT
```

- **TRIGGERED**: agent posted `@coderabbitai review`
- **ACKNOWLEDGED**: eyes reaction on trigger comment (delay: 0s–5min+)
- **ACCEPTED**: "Review triggered" ack posted (delay: 0s–5min+)
- **COMPLETED**: new review entry (`submitted_at > trigger_time`, `body != ""`)
- **TIMED_OUT**: timeout elapsed, no review output

ACKNOWLEDGED and ACCEPTED are **informational early signals** — they
confirm progress but must NOT be used for completion judgment.

No "Declined" state: eyes/ack delays of 5min+ were observed (PR #187
trigger 3). Timeout is the only way to determine non-response.

### Codex (3 states)

```text
TRIGGERED ──[review, submitted_at > t]──→ COMPLETED
TRIGGERED ──[👍 on trigger comment]──→ COMPLETED_CLEAN
TRIGGERED ──[timeout elapsed]──→ TIMED_OUT
```

- **COMPLETED**: review entry from `chatgpt-codex-connector[bot]`
- **COMPLETED_CLEAN**: thumbs-up on trigger comment (no findings)
- **TIMED_OUT**: timeout elapsed, no output

Codex produces NO intermediate signals (no eyes, no ack comment).

## Polling Algorithm

```text
INPUTS:
  trigger_time  — trigger comment created_at
  trigger_id    — trigger comment ID
  reviewer      — "coderabbit" | "codex"
  timeout       — 20 min (default)

POLL (every 30s):
  1. GET pulls/<N>/reviews
     → filter by reviewer login pattern
     → filter submitted_at > trigger_time
     → filter body != "" (exclude empty bot-to-bot replies)
     → if any → COMPLETED

  2. IF reviewer == "coderabbit":
     a. GET reactions on trigger_id → eyes > 0 → ACKNOWLEDGED
     b. GET issues/<N>/comments → filter CR bot,
        created_at > trigger_time, body contains "Review triggered"
        → ACCEPTED

  3. IF reviewer == "codex":
     a. GET reactions on trigger_id → "+1" > 0 → COMPLETED_CLEAN

  4. IF elapsed > timeout → TIMED_OUT
```

ACKNOWLEDGED/ACCEPTED are reported as progress but do NOT terminate
polling. Completion = COMPLETED | COMPLETED_CLEAN | RATE_LIMITED | TIMED_OUT.

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

**Codex**: Rate-limit behavior has not been observed. If Codex implements rate limiting in the future, detection should follow the same pattern (PR comment with identifiable message). Until observed, Codex rate-limit recovery is not actionable.

### Wait Time Parsing

The rate-limit comment contains an embedded wait time in bold:

> Please wait **4 minutes and 43 seconds** before requesting another review.

Extract with regex (applied to the comment body):

```regex
wait \*\*(\d+) minutes? and (\d+) seconds?\*\*
```

Convert to seconds: `minutes * 60 + seconds + 30` (30s safety buffer included).

### Recovery Flow

1. Detect RATE_LIMITED via PR comment (see Detection above)
2. Parse wait time from comment body (includes 30s buffer per formula above)
3. Sleep for `parsed_seconds`
4. Re-trigger: `gh pr comment <N> --body "@coderabbitai review"`
5. Reset both `trigger_time` and `trigger_id` to the new comment's `created_at` and ID, reset state to TRIGGERED, and resume normal polling
6. If a second RATE_LIMITED occurs: stop, report as TIMED_OUT

Maximum 1 recovery attempt per reviewer per PR.

## Edge Cases

- **Empty body review**: CodeRabbit replying to another bot's inline
  comment creates a review entry with `body: ""`. Always filter with
  `select(.body != "")` to avoid false completion signals.
- **Eyes/Ack delay**: Up to 5min+ observed (PR #187 trigger 3). These
  are unreliable for early termination — only timeout is definitive.
- **Codex thumbs-up vs findings**: When Codex finds no issues, it reacts
  with thumbs-up on the trigger comment instead of posting a review.
  Poll both `pulls/<N>/reviews` and trigger comment reactions.
- **Incremental review scope**: CodeRabbit reviews only new commits
  pushed after its last review. The "does not re-review already reviewed
  commits" note describes scope, not completion status.

## Timing

| | CodeRabbit | Codex |
|---|---|---|
| Typical completion | 2–7 min | 1–7 min |
| Eyes/Ack delay | 0s–5min+ | N/A |
| Polling interval | 30 s | 30 s |
| Timeout | 20 min | 20 min |

## CodeRabbit Pro/OSS Rate Limits

OSS repositories get Pro features free. Rate limits are generous:

| Resource | Limit |
|----------|-------|
| Files per hour | 200 |
| Back-to-back PR reviews | 3, then 4 reviews/hour |
| Chat messages | 25 back-to-back, then 50/hour |

### Re-review after review-fix

Agent re-triggers CodeRabbit after every review-fix push (`review-fix` Step 5b).
Agent decides whether to also re-trigger Codex.

| Condition | CodeRabbit | Codex |
|-----------|-----------|-------|
| Any push to PR branch | Agent triggers `@coderabbitai review` | — |
| Push addresses a Codex-sourced finding | Agent triggers `@coderabbitai review` | Yes — `@codex review` |
| Push addresses only CodeRabbit/Cursor findings | Agent triggers `@coderabbitai review` | No |

## Finding Integration

All bot findings receive the **same evaluation** in `pr-review` —
assessed on technical merit with P0/P1 classification. Cursor and
bot reviewers have equal weight.

When both reviewers are triggered, deduplicate findings where both
flagged the same issue. Note the source for traceability.

## Delegation

Bot review wait is delegated to a background subagent (main agent must
not block). See `agent--delegation-templates.md`:

- **Template 4**: CI + Bot Review Wait (after `pr-create`)
- **Template 5**: Bot Review Wait Only (after `review-fix` re-trigger)

Both templates poll all triggered reviewers in parallel.

## Related

- `agent--delegation-templates.md` — Template 4/5 implement the wait
  logic
- `.coderabbit.yaml` — CodeRabbit configuration (auto_review OFF,
  agent-triggered, assertive profile, path_instructions)
