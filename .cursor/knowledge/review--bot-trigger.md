---
trigger: bot review trigger, CodeRabbit trigger, Codex trigger, Two-Tier Trigger Model, @coderabbitai review, @codex review, trigger conditions
---
# Bot Review Trigger

Trigger rules for AI code reviewers on PRs. Covers CodeRabbit (primary)
and Codex Cloud (supplementary). All commands that interact with bot
reviewers (`pr-create`, `pr-review`, `review-fix`, `next`) reference
these atoms instead of embedding behavioral assumptions.

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

**Rate limit handling**: See `review--bot-timing.md` § Rate-Limit Detection
and Recovery Pattern for detection mechanics, and `subagent-policy.mdc`
§ Rate-Limit Recovery Policy for the decision (recover vs skip).

## Related

- `review--bot-detection.md` — output detection, state machine, polling
- `review--bot-timing.md` — timing, rate limits, recovery
- `review--bot-re-review.md` — re-review after review-fix
