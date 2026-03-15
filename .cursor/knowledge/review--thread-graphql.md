---
trigger: GraphQL thread enumeration, review thread query, unresolved thread count, thread baseline, PR review threads, isResolved
---
# Review Thread GraphQL Enumeration

Thread counts for completeness verification. Used by `pr-review`
(Step 6) and `review-fix` (Step 3b).

## Evidence-first approach

`make evidence-pull-request PR=<N>` provides:

- `reviews.threads_total` — total thread count
- `reviews.threads_unresolved` — unresolved count

Use this as the primary source. For per-thread detail (author, body,
isOutdated) needed during disposition reply composition, see
`review--consensus-protocol.md` § API Reference.

## Completeness check

- **Thread baseline**: X total, Y unresolved, Z resolved
- **Classified findings**: N (must equal Y for completeness)
- **Delta** (Y - N): if > 0, findings were missed — re-examine unresolved threads
