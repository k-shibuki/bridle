---
trigger: bot review detection, coderabbit detection, CodeRabbit completion, coderabbit polling, review ack vs completion, coderabbit done, coderabbit in progress, Polling Algorithm
---
# Bot Review Detection

Output detection, state machine, and polling algorithm for bot reviewers.

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
gh api repos/{owner}/{repo}/pulls/<N>/reviews \
  --jq '[.[] | select(.user.login | test("coderabbit"; "i")) | select(.body != "") | {id, state, body, submitted_at}]'

gh api repos/{owner}/{repo}/pulls/<N>/comments \
  --jq '[.[] | select(.user.login | test("coderabbit"; "i")) | {id, path, line: (.line // .original_line), body, created_at}]'

gh api repos/{owner}/{repo}/issues/<N>/comments \
  --jq '[.[] | select(.user.login | test("coderabbit"; "i")) | {id, body, created_at}]'
```

### Codex detection

Bot login pattern: `chatgpt-codex-connector|codex|openai`
(observed: `chatgpt-codex-connector[bot]`). Use the same three API
commands as CodeRabbit above, substituting the login pattern.

## State Detection

| State | Detection | Applies to |
|-------|-----------|------------|
| **TRIGGERED** | Agent posted trigger comment | Both |
| **ACKNOWLEDGED** | Eyes reaction on trigger comment | CodeRabbit only |
| **ACCEPTED** | "Review triggered" ack comment after trigger time | CodeRabbit only |
| **COMPLETED** | Review entry with `submitted_at > trigger_time` AND `body != ""` | Both |
| **COMPLETED_CLEAN** | Thumbs-up on trigger comment (no findings) | Codex only |
| **RATE_LIMITED** | PR comment contains "Rate limit exceeded" (see `review--bot-timing.md`) | Both |
| **TIMED_OUT** | Timeout elapsed, no completion signal | Both |

**Rule**: Always use API checks to determine state. Do not infer state
from timing or absence of activity. Classifying a bot as TIMED_OUT before
20 min has elapsed is prohibited — poll at 30s intervals until a terminal
state: COMPLETED, COMPLETED_CLEAN, RATE_LIMITED, or TIMED_OUT.

**Trigger time tracking**: Each trigger creates a new `trigger_time`
(the `created_at` of the trigger comment). All subsequent state
detection MUST filter by this specific `trigger_time`. When a reviewer
is re-triggered, the old `trigger_time` is invalidated. Always capture
the trigger comment ID and `created_at` at trigger time.

**Critical**: CodeRabbit's "Review triggered" ack is NOT completion —
it is an intermediate signal (ACCEPTED).

## State Machine

**CodeRabbit** (4 states + timeout):

```text
TRIGGERED ──[eyes]──→ ACKNOWLEDGED ──[ack]──→ ACCEPTED ──[review]──→ COMPLETED
any state ──[timeout]──→ TIMED_OUT
any state ──[rate limit]──→ RATE_LIMITED ──[retry]──→ TRIGGERED
RATE_LIMITED ──[second rate limit]──→ TIMED_OUT
```

All review transitions require `submitted_at > trigger_time` and `body != ""`.

**Codex** (3 states, no intermediate signals):

```text
TRIGGERED ──[review]──→ COMPLETED
TRIGGERED ──[👍 on trigger]──→ COMPLETED_CLEAN
TRIGGERED ──[timeout]──→ TIMED_OUT
```

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

## Edge Cases

- **Empty body review**: CodeRabbit replying to another bot creates a
  review with `body: ""`. Always filter with `select(.body != "")`.
- **Codex thumbs-up vs findings**: No issues → thumbs-up on trigger
  comment instead of review. Poll both reviews and reactions.
- **Incremental review scope**: CodeRabbit reviews only new commits
  pushed after its last review.

## Related

- `review--bot-trigger.md` — trigger rules and two-tier model
- `review--bot-timing.md` — timing, rate limits, recovery
- `review--bot-re-review.md` — re-review after review-fix
