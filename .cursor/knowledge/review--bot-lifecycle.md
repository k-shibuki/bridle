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
| **Primary** | CodeRabbit (Pro/OSS) | All PRs (auto) | Walkthrough, tool integrations (shellcheck, yamllint), AGENTS.md auto-detect, no rate limit concern |
| **Supplementary** | Codex Cloud | Complex PRs only | Cross-file logic consistency, deep semantic understanding |

Both reviewers read `AGENTS.md` and apply its review guidelines
(severity policy, S7 type safety, test quality). CodeRabbit additionally
uses `knowledge_base.code_guidelines.enabled: true` to detect the file.

## Trigger

**CodeRabbit**: Auto-review on every PR (`.coderabbit.yaml` `auto_review.enabled: true`).
No agent action required. Manual `@coderabbitai review` is used **only for re-review** after `review-fix`.

**Codex**: Triggered **manually** via PR comment for complex changes only.

```bash
# Codex (only for complex changes — R code, schemas, security, ADRs):
gh pr comment <PR> --body "@codex review"
```

Events that trigger CodeRabbit auto-review:
- PR open
- Push / synchronize (new commits on existing PR)

Events that do **NOT** trigger Codex:
- PR open / draft → ready (must be triggered manually)
- Push / synchronize
- Rebase, label changes, PR body edits

## Two-Tier Trigger Model

CodeRabbit auto-reviews **every PR** (Deterministic — no agent decision).
The agent only decides whether to trigger Codex (Steering — conditional).

| Change type | CodeRabbit | Codex | Rationale |
|-------------|-----------|-------|-----------|
| R code changes | Yes (auto) | **Yes** | Cross-file S7 class logic, NULL traps |
| Schema changes (`docs/schemas/`) | Yes (auto) | **Yes** | Schema-class consistency |
| Security-related changes | Yes (auto) | **Yes** | High risk, needs deep review |
| ADRs (`docs/adr/`) | Yes (auto) | **Yes** | Architecture-code alignment |
| CI config (`.github/workflows/`) | Yes (auto) | No | Breakage risk; yamllint covers syntax |
| Shell scripts (`tools/`) | Yes (auto) | No | shellcheck covers syntax |
| Workflow files (`.cursor/`) | Yes (auto) | No | Cross-reference consistency |
| Docs only (`.md`, non-ADR) | Yes (auto) | No | Low risk but still reviewed |

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
| **In progress** | Eyes reaction present (Codex only) | Codex |
| **Rate limited** | Body contains "usage limits" | Both |
| **Completion** | Output in ANY channel > 0 | Both |

**Rule**: Always use API checks to determine state. Do not infer state
from timing, absence of activity, or activity on other PRs.

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

CodeRabbit re-reviews automatically on every push (incremental auto-review).
The agent only decides whether to re-trigger Codex.

| Condition | CodeRabbit | Codex |
|-----------|-----------|-------|
| Any push to PR branch | Auto (incremental) | — |
| Push addresses a Codex-sourced finding | Auto (incremental) | Yes — `@codex review` |
| Push addresses only CodeRabbit/Cursor findings | Auto (incremental) | No |

Manual `@coderabbitai review` is only needed if incremental auto-review
is paused (after 5 reviewed commits — see Rate Limits above).

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
- `.coderabbit.yaml` — CodeRabbit configuration (auto_review ON,
  assertive profile, path_instructions)
