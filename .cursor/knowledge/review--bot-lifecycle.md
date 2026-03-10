---
trigger: bot review, Codex review, Codex trigger, @codex review, CodeRabbit, @coderabbitai review, eyes reaction, Codex lifecycle, Codex re-review, Codex rate limit, CodeRabbit rate limit, Codex wait, Codex Cloud Review, review fallback, coderabbit fallback, supplementary review, coderabbit detection
---
# Bot Review Lifecycle

Single source of truth for AI code review behavior on PRs. Covers
Codex Cloud (primary) and CodeRabbit Free Plan (fallback). All commands
that interact with bot reviewers (`pr-create`, `pr-review`, `review-fix`,
`next`) reference this atom instead of embedding behavioral assumptions.

## Reviewers

| Reviewer | Role | Trigger | Auto-review |
|----------|------|---------|-------------|
| **Codex Cloud** | Primary | `@codex review` comment | OFF |
| **CodeRabbit** (Free Plan) | Fallback (Codex rate-limited only) | `@coderabbitai review` comment | OFF (`.coderabbit.yaml`) |

Both reviewers read `AGENTS.md` and apply its review guidelines
(severity policy, S7 type safety, test quality). CodeRabbit additionally
uses `knowledge_base.code_guidelines.enabled: true` to detect the file.

## Trigger

Bot review is triggered **only** by explicit PR comments. Auto-review
is OFF for both reviewers.

```bash
# Primary (always triggered first)
gh pr comment <PR> --body "@codex review"

# Fallback (triggered by subagent only when Codex is RATE_LIMITED)
gh pr comment <PR> --body "@coderabbitai review"
```

Events that do **NOT** trigger either reviewer:
- PR open / draft → ready
- Push / synchronize (new commits on existing PR)
- Rebase, label changes, PR body edits

## Fallback Decision Tree

Executed by the background subagent (Template 4/5):

```
Codex result?
├── REVIEWED       ──→ Use Codex findings (no fallback)
├── TIMEOUT        ──→ Proceed without bot review (no fallback)
└── RATE_LIMITED   ──→ Trigger @coderabbitai review
                       ├── REVIEWED     ──→ Use CodeRabbit findings
                       ├── TIMEOUT      ──→ Proceed without bot review
                       └── RATE_LIMITED  ──→ Proceed without bot review
```

## Output Detection

Both reviewers produce output through three API channels:

| Channel | API endpoint | Codex | CodeRabbit |
|---------|-------------|-------|------------|
| **Review** | `pulls/<N>/reviews` | Summary + state: COMMENTED | Review with state |
| **Inline comments** | `pulls/<N>/comments` | Line-level findings (P0/P1 badges) | Line-level findings |
| **PR comment** | `issues/<N>/comments` | "Didn't find any major issues" (clean bill) | Walkthrough summary |

### Codex detection

Bot login pattern: `codex|openai` (or `user.type == "Bot"`).

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

| | Codex | CodeRabbit |
|---|---|---|
| Typical completion | 1–5 min | 2–5 min |
| Polling interval | 30 s | 30 s |
| Timeout | 7 min | 7 min |

## CodeRabbit Free Plan Rate Limits

| Resource | Limit |
|----------|-------|
| Files per hour | 200 |
| Back-to-back PR reviews | 3, then 4 reviews/hour |
| Chat messages | 25 back-to-back, then 50/hour |

## Agent Decision: When to Request Bot Review

| Change type | Request? | Rationale |
|-------------|----------|-----------|
| R code changes | Yes | Core functionality |
| Shell scripts (`tools/`) | Yes | CI policy gates |
| Schema changes (`docs/schemas/`) | Yes | Domain-critical |
| Security-related changes | Yes | High risk |
| Docs only (`.md`, ADRs) | No | Low risk |
| Workflow files (`.cursor/`) | No | Agent workflow, not code |
| CI config (`.github/workflows/`) | No | YAML config |

### Re-review after review-fix

| Condition | Re-trigger? |
|-----------|------------|
| Addressed a bot P0 finding with code change | Yes |
| Addressed a bot P1 finding with significant code change | Yes |
| Minor fix, docs, or workflow adjustment | No |
| Bot review was not requested in initial review | No |

Re-trigger always starts with `@codex review`. If Codex is still
rate-limited, the subagent falls back to `@coderabbitai review`.

## Finding Integration

All bot findings receive the **same evaluation** in `pr-review` —
assessed on technical merit with P0/P1 classification. Cursor, Codex,
and CodeRabbit have equal weight; none is authoritative over the others.

When CodeRabbit is used as fallback, the merge recommendation template
shows "CodeRabbit (fallback)" and `review-fix` treats its inline
comments identically to Codex.

## Delegation

Bot review wait is delegated to a background subagent (main agent must
not block). See `agent--delegation-templates.md`:

- **Template 4**: CI + Bot Review Wait (after `pr-create`)
- **Template 5**: Bot Review Wait Only (after `review-fix` re-trigger)

Both templates include the CodeRabbit fallback path.

## Related

- `agent--delegation-templates.md` — Template 4/5 implement the wait +
  fallback logic
- `.coderabbit.yaml` — CodeRabbit configuration (auto_review OFF,
  assertive profile, path_instructions)
