---
trigger: Codex review, Codex trigger, @codex review, bot review, eyes reaction, Codex lifecycle, Codex re-review, Codex rate limit, Codex wait, Codex Cloud Review
---
# Codex Cloud Review Lifecycle

Single source of truth for Codex Cloud Review behavior. All commands
that interact with Codex (`pr-create`, `pr-review`, `review-fix`, `next`)
reference this atom instead of embedding behavioral assumptions.

## Trigger

Codex reviews are triggered **only** by an explicit `@codex review`
comment on the PR. Automatic review on PR open is **OFF** for this
repository.

```bash
gh pr comment <PR> --body "@codex review"
```

Events that do **NOT** trigger Codex:
- PR open / draft → ready (auto-review disabled)
- Push / synchronize (new commits on existing PR)
- Rebase, label changes, PR body edits

## Output

Codex produces output through **three channels** depending on whether it
finds issues:

### When findings exist (P0/P1 comments)

1. **Top-level review** — `pulls/<N>/reviews` API, `state: "COMMENTED"`,
   `user.type: "Bot"`. Contains summary header.
2. **Inline comments** — `pulls/<N>/comments` API with `path`, `line`,
   and `body` fields. Each carries a severity badge (P0/P1).

### When no findings exist

3. **PR comment** — `issues/<N>/comments` API (not a review, not inline).
   Body contains "Didn't find any major issues" or similar clean-bill
   message, often with a 👍 reaction.

## State Detection (API-based, no guessing)

All three channels must be checked to determine Codex completion:

| State | Detection | Commands |
|-------|-----------|----------|
| **Reviewed (with findings)** | Bot review exists in reviews API | `gh api repos/{owner}/{repo}/pulls/<N>/reviews --jq '[.[] \| select(.user.type == "Bot" or (.user.login \| test("codex\|openai"; "i")))]'` |
| **Reviewed (no findings)** | Bot comment exists in PR comments | `gh api repos/{owner}/{repo}/issues/<N>/comments --jq '[.[] \| select(.user.type == "Bot" or (.user.login \| test("codex\|openai"; "i")))]'` |
| **Inline findings** | Bot inline comments on specific lines | `gh api repos/{owner}/{repo}/pulls/<N>/comments --jq '[.[] \| select(.user.type == "Bot" or (.user.login \| test("codex\|openai"; "i")))]'` |
| **In progress** | Eyes reaction present | `gh api repos/{owner}/{repo}/issues/<N>/reactions --jq '[.[] \| select(.content == "eyes")]'` |
| **Rate limited** | Review/comment body contains "usage limits" | Check body text of any bot output |

**Completion** = bot output in ANY of the three channels (reviews, inline
comments, or PR comments). The eyes reaction alone does NOT mean complete.

**Rule**: Always use these API checks to determine state. Do not infer
state from timing, absence of activity, or activity on other PRs.

## Timing

- Typical completion: 1–5 minutes (varies with diff size)
- Polling interval: 30 seconds
- Timeout: 7 minutes (after which, proceed without Codex)

## Agent Decision: When to Request Codex Review

The agent decides whether to request Codex review. Guidelines:

| Change type | Request Codex? | Rationale |
|-------------|---------------|-----------|
| R code changes | Yes | Core functionality |
| Shell scripts (`tools/`) | Yes | CI policy gates |
| Schema changes (`docs/schemas/`) | Yes | Domain-critical |
| Security-related changes | Yes | High risk |
| Docs only (`.md`, ADRs) | No | Low risk, Codex adds little value |
| Workflow files (`.cursor/`) | No | Agent workflow, not code |
| CI config (`.github/workflows/`) | No | YAML config |

### Re-review after review-fix

| Condition | Re-trigger? |
|-----------|------------|
| Addressed a Codex P0 finding with code change | Yes |
| Addressed a Codex P1 finding with significant code change | Yes |
| Minor fix, docs, or workflow adjustment | No |
| Codex was not requested in initial review | No |

## Delegation

Codex wait is delegated to a background subagent (main agent must not
block). See `agent--delegation-templates.md`:

- **Template 4**: CI + Codex Wait (after `pr-create`)
- **Template 5**: Codex-Wait Only (after `review-fix` re-trigger)
