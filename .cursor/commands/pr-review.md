# pr-review

## Purpose

Review a pull request and produce a merge recommendation. This command produces judgment only — merge execution is `pr-merge`, fix execution is `review-fix`.

## Inputs (ask if missing)

- PR number or URL (required)

## Sense

1. Run `make evidence-pull-request PR=<N>` for structured PR state (CI, merge, reviews, threads, traceability).
2. Retrieve the diff: `gh pr diff <N>`
3. Retrieve the linked Issue's DoD: `gh issue view <issue-number>`

## Orient

### Review criteria

Consult `AGENTS.md` § Review guidelines for severity policy (P0/P1 only) and category-specific rules. Key categories:

| Category | Knowledge / Principle source |
|----------|------------------------------|
| Issue DoD | Issue acceptance criteria |
| Code quality | `AGENTS.md` § Review guidelines |
| Spec alignment | `docs/adr/` |
| Type safety | `AGENTS.md` § S7 type safety |
| Test quality | `test-strategy.mdc`, `AGENTS.md` § Test quality |
| Traceability | `workflow-policy.mdc` § Issue-Driven Workflow |
| Security | `AGENTS.md` § Security |

### Bot review integration

Consult `review--bot-operations.md` for detection, timing, and terminal states. Check evidence field `reviews.bot_coderabbit.status`:

| Status | Action |
|--------|--------|
| COMPLETED | Include findings in review (deduplicate with Cursor findings) |
| COMPLETED_CLEAN / COMPLETED_SILENT | Note "no findings" |
| RATE_LIMITED / TIMED_OUT | Note in report; proceed without |
| NOT_TRIGGERED | Note with reason |

### FSM context

This command runs in state **ReadyForReview** (CI green, bot review complete). Valid transitions: → ReviewDone (mergeable) or → ChangesRequired.

## Act

### 1. Perform code review

Review the diff against each category. Evaluate bot findings on technical merit — Cursor and bot reviewers have equal weight.

### 2. Verify thread baseline

Use evidence field `reviews.threads_total` and `reviews.threads_unresolved`. Confirm classified findings count matches unresolved thread count.

### 3. Produce merge recommendation

```text
## Merge decision

### Conclusion: Mergeable / Changes required
### Merge strategy: squash / merge
### Issue DoD check
- [ ] Criterion 1: met / not met

### Bot review status
- CodeRabbit: <status> | Codex: <status>
- Findings incorporated: <count>

### Cursor findings
- <evidence per category>

### Required changes (if any)
1. Fix xxx (source: Cursor/bot)
```

If "Mergeable" → recommend `pr-merge`. If "Changes required" → recommend `review-fix`.

## Guard / Validation

- CI must be green before review (`HS-CI-MERGE`)
- Bot review freshness: `reviews.bot_coderabbit.review_submitted_at > reviews.last_push_at`
- Thread completeness: classified findings == unresolved threads

> **Observation gap**: All external state is acquired via `make` evidence targets. If information is not available from any target, report it as a missing evidence target.

> **Anti-pattern — judgment creep**: Review criteria belong in `AGENTS.md` and Knowledge atoms. This procedure routes to them — it does not duplicate them.

## Related

- `AGENTS.md` — review guidelines (SSOT for severity, categories)
- `review--bot-operations.md` — bot detection, timing, polling
- `review--consensus-protocol.md` — consensus model
- `review-fix.md` — fix findings from this review
- `pr-merge.md` — next step when mergeable
