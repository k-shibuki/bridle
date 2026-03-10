# pr-review

## Purpose

Review a pull request: inspect the diff, verify CI status, check Issue DoD fulfillment, incorporate bot review feedback (if available), and produce a merge recommendation.

**This command produces a judgment only.** Merge execution is handled by `pr-merge`. If changes are required, delegate fixes to `review-fix`.

## When to use

- After `pr-create` and CI has run
- When reviewing a PR from another contributor or AI agent
- As **manual fallback** when bot reviewers are unavailable (both rate limited or not configured)

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

### 6. Retrieve bot review findings

**Prerequisite**: Read `@.cursor/knowledge/review--bot-lifecycle.md` (SSOT for detection commands, login patterns, and state signals).

Bot review is triggered in `pr-create` Step 5 (or `review-fix` Step 5b) and waited on by a background subagent. The subagent tries the primary reviewer first; if rate-limited, it falls back to the secondary. By the time `pr-review` runs, the subagent has already reported which reviewer responded.

Use the detection commands from `review--bot-lifecycle.md` § Output Detection to retrieve findings from whichever reviewer responded (primary or secondary).

| Status | Action |
|--------|--------|
| **Reviewed (findings)** | Include bot findings in Step 7 |
| **Reviewed (clean)** | Note "Bot review: no findings" in report |
| **Both rate-limited** | Note in report; proceed without bot review |
| **Timeout** | Note in report; proceed without bot review |
| **Not requested** | Note "Bot review: not requested" with reason |

When re-reviewing after `review-fix`: check the bot review `submitted_at` timestamp against the latest commit date. Use only the most recent bot review.

### 7. Code review

Perform the Cursor-side review, then integrate any bot findings.

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

**Bot findings integration** (if bot review status is "Reviewed"):

Evaluate each bot comment on technical merit — Cursor and bot reviewers have equal weight:
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

### Bot review status
- Status: Reviewed (<reviewer>) / Both rate-limited / Timeout / Not requested
- Findings incorporated: <count> (valid: N, false positive: N)

### Cursor findings
- <evidence for each category>

### Required changes (if any)
1. Fix xxx (source: Cursor)
2. Fix yyy (source: bot review)
```

If the conclusion is "Mergeable", recommend running `pr-merge` as the next step.

If the conclusion is "Changes required", recommend running `review-fix` to address all findings, then re-running `pr-review`.

## Output (response format)

- **PR summary**: title, branch, files changed, diff size
- **Issue**: `#<number>` linked, DoD fulfillment status
- **CI status**: pass / fail (with details)
- **Bot review status**: reviewed (<reviewer>) / both rate-limited / timeout / not requested
- **Review findings**: grouped by category, with source (Cursor / bot review)
- **Merge decision**: mergeable (recommended strategy) / changes required (list)
- **Next step**: `pr-merge` (if mergeable) / `review-fix` (if changes required)

## Related

- `@.cursor/commands/review-fix.md` (fix findings from this review)
- `@.cursor/commands/pr-merge.md` (next step when mergeable)
- `@.cursor/commands/pr-create.md` (PR creation)
- `@.cursor/rules/test-strategy.mdc` (test quality criteria)
