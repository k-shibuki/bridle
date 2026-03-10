# pr-review

## Purpose

Review a pull request: inspect the diff, verify CI status, check Issue DoD fulfillment, incorporate Codex Cloud review feedback (if available), and produce a merge recommendation.

**This command produces a judgment only.** Merge execution is handled by `pr-merge`. If changes are required, delegate fixes to `review-fix`.

## When to use

- After `pr-create` and CI has run
- When reviewing a PR from another contributor or AI agent
- As **manual fallback** when Codex Cloud Review is unavailable (rate limited or not configured)

## Contract

1. Read all user-attached `@...` context first (PR description, diff, requirements).
2. If required context is missing, ask for the exact `@...` files/info and stop.
3. Do NOT execute merge. Always delegate merge to `pr-merge`.
4. Do NOT execute fixes. Always delegate fixes to `review-fix`.

## Inputs (ask if missing)

- PR number or URL (required)
- Requirements/acceptance criteria (`@docs/adr/`) (recommended)

## Steps

### 1. Gather PR context

```bash
gh pr view <PR-number> --json title,body,files,commits,reviews,checks
```

### 2. Verify Issue linkage

Check that the PR body contains `Closes #<issue>` or `Fixes #<issue>`. If missing and no exception label (`no-issue`) is present, flag this as a required change.

```bash
gh pr view <PR-number> --json body --jq '.body'
```

### 3. Retrieve the linked Issue's DoD

```bash
gh issue view <issue-number>
```

Extract the acceptance criteria / Definition of Done from the Issue.

### 4. Inspect the diff

```bash
gh pr diff <PR-number>
```

### 5. Verify CI status

```bash
gh pr checks <PR-number>
```

All required checks must pass. If any check fails, the PR is not ready for merge.

### 6. Check Codex Cloud review status

Check whether Codex has reviewed this PR and what it found.

```bash
# Fetch bot reviews (top-level)
gh api repos/{owner}/{repo}/pulls/<PR>/reviews \
  --jq '[.[] | select(.user.type == "Bot" or (.user.login | test("codex|openai"; "i"))) | {id, state, body, submitted_at}]'

# Fetch bot inline comments
gh api repos/{owner}/{repo}/pulls/<PR>/comments \
  --jq '[.[] | select(.user.type == "Bot" or (.user.login | test("codex|openai"; "i"))) | {id, path, line: (.line // .original_line), body, created_at}]'
```

Classify the Codex review status:

| Status | Signals | Action |
|--------|---------|--------|
| **Reviewed** | Bot review comments exist | Include Codex findings in the review below |
| **In progress** | PR has reaction (eyes emoji) but no review yet | Note in report; do not block on it |
| **Rate limited** | "usage limits" comment from Codex | Note in report; proceed without Codex input |
| **Not configured** | No bot activity at all | Note in report; proceed without Codex input |

### 7. Code review

Perform the Cursor-side review, then integrate any Codex findings.

**Cursor review categories:**

| Category | What to check |
|---------|---------------|
| **Issue DoD** | all acceptance criteria from the Issue are met |
| **Change overview** | files changed, diff size |
| **Code quality** | readability, naming, duplication |
| **Spec alignment** | aligns with ADRs (`docs/adr/`) |
| **Type safety** | S7 properties have explicit types, no `class_any` |
| **Test quality** | (1) test matrix exists and matches change surface, (2) positive/negative balance acceptable, (3) boundary cases covered (0/min/max/±1/empty/NULL), (4) Given/When/Then comments present, (5) exceptions validate type+message, (6) branch coverage reasonable, (7) new params have wiring/effect tests |
| **Traceability** | `Closes #<issue>` present, `Refs: #<issue>` in commits |
| **Security** | authentication, authorization, network boundary, or credential changes flagged |
| **Risk / Rollback** | risk assessment and rollback plan documented in PR |

**Codex findings integration** (if Codex status is "Reviewed"):

Evaluate each Codex comment on technical merit — Cursor and Codex have equal weight:
- **Valid**: add to findings (deduplicate if Cursor flagged the same issue)
- **False positive**: note with reason; if a pattern recurs, flag for knowledge atom creation (`.cursor/knowledge/review--*.md`)

### 8. Produce merge recommendation

```text
## Merge decision

### Conclusion: Mergeable / Changes required

### Merge strategy: squash / merge
- Reason: (e.g., "AI-created PR with many micro-commits")

### Issue DoD check
- [ ] Criterion 1: met / not met
- [ ] Criterion 2: met / not met

### Codex review status
- Status: Reviewed / In progress / Rate limited / Not configured
- Findings incorporated: <count> (valid: N, false positive: N)

### Cursor findings
- <evidence for each category>

### Required changes (if any)
1. Fix xxx (source: Cursor)
2. Fix yyy (source: Codex)
```

If the conclusion is "Mergeable", recommend running `pr-merge` as the next step.

If the conclusion is "Changes required", recommend running `review-fix` to address all findings, then re-running `pr-review`.

## Output (response format)

- **PR summary**: title, branch, files changed, diff size
- **Issue**: `#<number>` linked, DoD fulfillment status
- **CI status**: pass / fail (with details)
- **Codex status**: reviewed / in progress / rate limited / not configured
- **Review findings**: grouped by category, with source (Cursor / Codex)
- **Merge decision**: mergeable (recommended strategy) / changes required (list)
- **Next step**: `pr-merge` (if mergeable) / `review-fix` (if changes required)

## Related

- `@.cursor/commands/review-fix.md` (fix findings from this review)
- `@.cursor/commands/pr-merge.md` (next step when mergeable)
- `@.cursor/commands/pr-create.md` (PR creation)
- `@.cursor/rules/test-strategy.mdc` (test quality criteria)
