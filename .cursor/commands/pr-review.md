# pr-review

## Purpose

Review a pull request and produce a merge recommendation. This command produces judgment only — merge execution is `pr-merge`, fix execution is `review-fix`.

## Inputs (ask if missing)

- PR number or URL (required)

## Sense

1. Run `make evidence-pull-request PR=<N>` for structured PR state (CI, merge, reviews, threads, traceability).
2. Retrieve the diff: `gh pr diff <N>`
3. Retrieve the linked Issue's DoD: `make evidence-issue ISSUE=<issue-number>` (use the `body` field for acceptance criteria and test plan text)

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
- Bot review freshness: bot reached a terminal state covering the latest push. For COMPLETED: `review_submitted_at > last_push_at`. For COMPLETED_SILENT: terminal-state evaluation per `review--bot-operations.md` § Terminal States (no timestamp required).
- Thread completeness: classified findings == unresolved threads

> **Observation boundary**: Observation commands MUST use `make evidence-*` targets (`HS-EVIDENCE-FIRST`). Execution commands use raw CLI. Polling MUST be delegated (`HS-NO-INLINE-POLL`). See `controls--observation-execution-boundary.md`.

> **Anti-pattern — judgment creep**: Review criteria belong in `AGENTS.md` and Knowledge atoms. This procedure routes to them — it does not duplicate them.

## Related

- `AGENTS.md` — review guidelines (SSOT for severity, categories)
- `review--bot-operations.md` — bot detection, timing, polling
- `review--consensus-protocol.md` — consensus model
- `review-fix.md` — fix findings from this review
- `pr-merge.md` — next step when mergeable
