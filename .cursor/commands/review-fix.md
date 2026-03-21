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
6. Trigger re-review if CR budget remaining: `gh pr comment <PR> --body "@coderabbitai review"`. After posting, **do not** treat review as settled from a single snapshot where `threads_unresolved == 0` alone; CodeRabbit may still be posting threads or has not yet submitted a pull review answering this trigger (see `reviews.re_review_signal` in `docs/agent-control/evidence-schema.md` Target 4).
7. **Order**: (1) If Step 6 ran this cycle, either **delegate** review completion via `delegation--review-wait.md` (same trigger `created_at` / `trigger_id` semantics as `review--bot-operations.md` § Polling / Terminal States / `COMPLETED_SILENT`) **or** re-run `make evidence-pull-request PR=<N>` until `reviews.re_review_signal.cr_response_pending_after_latest_trigger == false`. (2) Then apply skip rules: if `threads_unresolved == 0` **and** `cr_response_pending_after_latest_trigger == false` **and** `auto_merge_readiness.review_consensus_complete` (or `auto_merge_readiness.safe_to_enable` when merge is the goal) → skip further delegation; otherwise → delegate via `delegation--review-wait.md` (Task: see template header for `run_in_background` — `true` for concurrent multi-PR waits; single-PR foreground default per `subagent-policy.mdc`).

## Output

- Findings addressed: count by source and severity
- False positives: count with reasons
- Quality gate: pass/fail
- Next step recommendation

## Guard

- `HS-REVIEW-RESOLVE`: every thread gets disposition reply before resolve
- `HS-NO-DISMISS`: every finding is evaluated on merit
- `HS-LOCAL-VERIFY`: pre-push hook validates
