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

Codex produces two kinds of output on the PR:

1. **Top-level review** — appears in `pulls/<N>/reviews` API with
   `state: "COMMENTED"` and `user.type: "Bot"`.
2. **Inline comments** — appears in `pulls/<N>/comments` API with
   `path`, `line`, and `body` fields. Each may carry a severity badge
   (P0/P1).

## State Detection (API-based, no guessing)

| State | Detection command | Condition |
|-------|-------------------|-----------|
| **Reviewed** | `gh api repos/{owner}/{repo}/pulls/<N>/reviews --jq '[.[] \| select(.user.type == "Bot" or (.user.login \| test("codex\|openai"; "i")))]'` | Result is non-empty |
| **Inline findings** | `gh api repos/{owner}/{repo}/pulls/<N>/comments --jq '[.[] \| select(.user.type == "Bot" or (.user.login \| test("codex\|openai"; "i")))]'` | Result is non-empty |
| **In progress** | `gh api repos/{owner}/{repo}/issues/<N>/reactions --jq '[.[] \| select(.content == "eyes")]'` | Eyes reaction (👀) present |
| **Rate limited** | Check review/comment body | Contains "usage limits" |

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
