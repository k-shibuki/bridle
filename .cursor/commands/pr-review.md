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
3. Per `@.cursor/rules/workflow-policy.mdc` § Command Separation of Concerns: this command produces judgment only — merge and fix execution are delegated to `pr-merge` and `review-fix` respectively.

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

**Prerequisite**: Read `@.cursor/knowledge/review--bot-detection.md` (SSOT for detection commands, login patterns, and state signals).

Bot reviews are triggered in `pr-create` Step 5 (or `review-fix` Step 5b) and polled by a background subagent. By the time `pr-review` runs, the subagent has reported which reviewers responded.

**Recovery checkpoint**: If bot review wait was not delegated to a subagent before `pr-review` started:

- **Action**: Delegate now per `@.cursor/rules/subagent-policy.mdc` (`agent--delegation-templates.md` Template 5) before proceeding.
- **Polling rule**: Inline polling by the main agent is prohibited — except in the sequential fallback case defined in `subagent-policy.mdc` § Fallback (non-subagent environments), where inline sequential polling is permitted.
- **Timeout**: TIMED_OUT = 20 min elapsed per `review--bot-timing.md` § Timing.
- **Intermediate states**: ACKNOWLEDGED and ACCEPTED mean the bot is still processing.

Use the detection commands from `review--bot-detection.md` § Output Detection to scan **all known reviewers** (CodeRabbit and Codex), regardless of whether the agent triggered them. Reviews from external sources (user via GitHub GUI, GitHub App auto-trigger, other bots) are equally valid review sources.

| Reviewer | Status | Action |
|----------|--------|--------|
| CodeRabbit | **Reviewed (findings)** | Include findings in Step 7 |
| CodeRabbit | **Reviewed (clean)** | Note "CodeRabbit: no findings" |
| CodeRabbit | **RATE_LIMITED / TIMED_OUT** | Note in report; proceed without. "TIMED_OUT" = 20 min elapsed per `review--bot-timing.md` § Timing |
| Codex | **Reviewed (findings)** | Include findings in Step 7 |
| Codex | **Reviewed (clean)** | Note "Codex: no findings" |
| Codex | **RATE_LIMITED / TIMED_OUT** | Note in report; proceed without. "TIMED_OUT" = 20 min elapsed per `review--bot-timing.md` § Timing |
| Either | **Externally reviewed** | Include findings (not agent-triggered but valid) |
| Either | **Not triggered** | Note "not triggered" with reason |

When both reviewers produce findings, deduplicate (same file + same issue = one finding, note both sources). When re-reviewing after `review-fix`: check `submitted_at` timestamps against the latest commit date. Use only the most recent review from each reviewer.

**Thread enumeration** (completeness baseline): After collecting findings, enumerate all review threads via GraphQL to establish a baseline for `review-fix`:

```bash
gh api graphql -f query='
  query($owner: String!, $repo: String!, $pr: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $pr) {
        reviewThreads(first: 100) {
          totalCount
          nodes { id isResolved isOutdated
            comments(first: 1) { nodes { author { login } body } }
          }
        }
      }
    }
  }
' -f owner={owner} -f repo={repo} -F pr=<N> --jq '{
  total: .data.repository.pullRequest.reviewThreads.totalCount,
  unresolved: [.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved | not)] | length,
  resolved: [.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved)] | length
}'
```

Report in the review output:
- **Thread baseline**: X total, Y unresolved, Z resolved
- **Classified findings**: N (must equal Y for completeness)
- **Delta** (Y - N): if > 0, findings were missed — re-examine unresolved threads

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
- CodeRabbit: Reviewed / Rate-limited / Timeout / Not triggered
- Codex: Reviewed / Rate-limited / Timeout / Not triggered
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
- **Bot review status**: per-reviewer (CodeRabbit / Codex): reviewed / rate-limited / timeout / not triggered
- **Review findings**: grouped by category, with source (Cursor / bot review)
- **Merge decision**: mergeable (recommended strategy) / changes required (list)
- **Next step**: `pr-merge` (if mergeable) / `review-fix` (if changes required)

## Related

- `@.cursor/commands/review-fix.md` (fix findings from this review)
- `@.cursor/commands/pr-merge.md` (next step when mergeable)
- `@.cursor/commands/pr-create.md` (PR creation)
- `@.cursor/rules/test-strategy.mdc` (test quality criteria)
- `@.cursor/knowledge/review--comment-response.md` (reply format, resolve procedure, completeness invariant)
