# review-fix

## Reads

- `review--consensus-protocol.md` (disposition categories, reply templates, consensus flow, reviewer unavailable handling)
- `review--bot-operations.md` (agreement mechanics, re-review budget, rate-limit recovery)

## Sense

1. `make evidence-pull-request PR=<N>` for thread state.
2. `make evidence-review-threads PR=<N>` for per-thread details (bodies, replies, GraphQL IDs).

## Act

1. Classify each finding: P0 (must fix) / P1 (should fix) / False positive / Already addressed.
2. Fix P0/P1 findings in priority order.
3. Post disposition replies per `review--consensus-protocol.md` (Fixed / By design / False positive / Acknowledged). Seek consensus per § Consensus Flow.
4. `make format-verify` — fix any failures.
5. Commit and push: `git add -A && git commit -m "fix(<scope>): address review feedback\n\nRefs: #<issue>" && git push`.
6. Trigger re-review if CR budget remaining: `gh pr comment <PR> --body "@coderabbitai review"`.
7. One-shot check: `make evidence-pull-request PR=<N>`. If `threads_unresolved == 0 AND auto_merge_readiness.review_consensus_complete` (or `auto_merge_readiness.safe_to_enable` when merge is the goal) → skip delegation. Otherwise → delegate via `delegation--review-wait.md` (Task: see template header for `run_in_background` — `true` for concurrent multi-PR waits; single-PR foreground default per `subagent-policy.mdc`).

## Output

- Findings addressed: count by source and severity
- False positives: count with reasons
- Quality gate: pass/fail
- Next step recommendation

## Guard

- `HS-REVIEW-RESOLVE`: every thread gets disposition reply before resolve
- `HS-NO-DISMISS`: every finding is evaluated on merit
- `HS-LOCAL-VERIFY`: pre-push hook validates
