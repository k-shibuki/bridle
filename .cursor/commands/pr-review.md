# pr-review

## Reads

- `AGENTS.md` § Review guidelines (severity: P0/P1 only, category rules)
- `review--bot-operations.md` (detection, terminal states, agreement mechanics)
- `test-strategy.mdc` (test quality: P0 if missing, P1 if incomplete)

## Sense

1. `make evidence-pull-request PR=<N>`
2. `gh pr diff <N>`
3. `make evidence-issue ISSUE=<linked-issue>` (for DoD verification)

## Act

1. Review diff against each `AGENTS.md` category (S7 type safety, test quality, architecture/ADR compliance, traceability, security, code quality/naming/duplication, NULL handling).
2. Integrate bot findings: check `reviews.bot_coderabbit.status` from evidence. Deduplicate with Cursor findings.
3. Verify thread baseline: `reviews.threads_total` and `reviews.threads_unresolved` match classified findings.
4. Produce merge recommendation: **Mergeable** → recommend `pr-merge`. **Changes required** → recommend `review-fix`.

## Output

- Merge decision + strategy (squash/merge per `workflow--merge-strategy.md`)
- Issue DoD check (met/not met per criterion)
- Bot review status + findings incorporated
- Required changes list (if any, with source and severity)

## Guard

- `HS-CI-MERGE`: CI must be green before merge (review may start earlier)
- Bot review freshness: terminal state covering latest push
