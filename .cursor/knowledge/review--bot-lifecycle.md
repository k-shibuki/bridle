---
trigger: bot review, Codex review, Codex trigger, @codex review, CodeRabbit, @coderabbitai review, eyes reaction, Codex lifecycle, Codex re-review, Codex rate limit, CodeRabbit rate limit, Codex wait, Codex Cloud Review, review fallback, coderabbit fallback, supplementary review, coderabbit detection
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

**Rate limit handling**: If either reviewer is rate-limited, proceed
without it. No fallback chain — each reviewer is independent.

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
# Reviews
gh api repos/{owner}/{repo}/pulls/<N>/reviews \
  --jq '[.[] | select(.user.login | test("coderabbit"; "i")) | {id, state, body, submitted_at}]'

# Inline comments
gh api repos/{owner}/{repo}/pulls/<N>/comments \
  --jq '[.[] | select(.user.login | test("coderabbit"; "i")) | {id, path, line: (.line // .original_line), body, created_at}]'

# Walkthrough / summary
gh api repos/{owner}/{repo}/issues/<N>/comments \
  --jq '[.[] | select(.user.login | test("coderabbit"; "i")) | {id, body, created_at}]'
```

### Codex detection

Bot login pattern: `codex|openai`.

```bash
# Reviews
gh api repos/{owner}/{repo}/pulls/<N>/reviews \
  --jq '[.[] | select(.user.type == "Bot" or (.user.login | test("codex|openai"; "i"))) | {id, state, body, submitted_at}]'

# Inline comments
gh api repos/{owner}/{repo}/pulls/<N>/comments \
  --jq '[.[] | select(.user.type == "Bot" or (.user.login | test("codex|openai"; "i"))) | {id, path, line: (.line // .original_line), body, created_at}]'

# PR comments
gh api repos/{owner}/{repo}/issues/<N>/comments \
  --jq '[.[] | select(.user.type == "Bot" or (.user.login | test("codex|openai"; "i"))) | {id, body, created_at}]'
```

## State Detection

| State | Detection | Applies to |
|-------|-----------|------------|
| **Reviewed (findings)** | Bot review + inline comments exist | Both |
| **Reviewed (clean)** | Bot PR/walkthrough comment exists | Both |
| **In progress** | Trigger ack posted, no new review/walkthrough after trigger time | CodeRabbit |
| **In progress** | Eyes reaction present | Codex |
| **Rate limited** | Body contains "usage limits" | Both |
| **Completion** | New review or walkthrough with timestamp > trigger time | Both |

**Rule**: Always use API checks to determine state. Do not infer state
from timing, absence of activity, or activity on other PRs.

**Critical**: CodeRabbit's "Review triggered" ack is NOT completion.
See `review--coderabbit-completion-signals.md` for the correct polling
algorithm and common mistakes.

## Timing

| | CodeRabbit | Codex |
|---|---|---|
| Typical completion | 2–5 min | 1–5 min |
| Polling interval | 30 s | 30 s |
| Timeout | 7 min | 7 min |

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
