# pr-merge

## Reads
- `controls--merge-invariants.md` (5 mandatory preconditions, merge state resolution, auto-merge decision)
- `workflow--merge-strategy.md` (squash vs merge selection, high-risk change policy)

## Sense

`make evidence-pull-request PR=<N>` — extract `ci.status`, `merge.merge_state_status`, `reviews.threads_unresolved`, `reviews.*` for `review_concluded`, and bot review freshness.

## Act

1. Verify all 5 preconditions from `controls--merge-invariants.md`. If any fails, STOP and report.
2. If `## Test Evidence` is empty, update PR body: `gh pr edit <N> --body "<updated>"`.
3. Merge (preferred: auto-merge): `gh pr merge <N> --auto <--squash|--merge>`. Fallback: delegated merge via `delegation--ci-wait-only.md`.
4. Post-merge: verify `state == "MERGED"` via `make evidence-pull-request PR=<N>`, then `make git-post-merge-cleanup BRANCH=<branch>`.

## Output
- Merge status: success/blocked (with reason)
- Merge strategy used
- Post-merge cleanup confirmation

## Guard
- `HS-CI-MERGE`: CI green required; `--admin` flag prohibited; amend+force-push prohibited
- `HS-CI-MERGE` auto-merge guard: MUST NOT set while bot review pending
- `HS-REVIEW-RESOLVE`: all threads resolved
