# review-fix

## Purpose

Address review findings from `pr-review`. Evaluate each finding, apply fixes, post disposition replies, and seek consensus per `review--consensus-protocol.md`.

## Inputs (ask if missing)

- **PR number** (required)
- **Scope** (optional): `all` (default), `p0-only`, or specific file path

## Sense

1. Run `make evidence-pull-request PR=<N>` for thread state.
2. Run `make evidence-review-threads PR=<N>` for per-thread details (bodies, replies, GraphQL IDs for resolution).
3. If `pr-review` was just run, use its "Required changes" list directly.

## Orient

### Finding classification

Evaluate every finding on technical merit regardless of source (Cursor and bot reviewers have equal weight):

| Classification | Action |
|---|---|
| **P0 (blocking)** | Must fix before merge |
| **P1 (significant)** | Should fix; document reason if deferring |
| **False positive** | Note reason; if recurring, create knowledge atom |
| **Already addressed** | Note the commit |

### Consensus protocol

Consult `review--consensus-protocol.md` (SSOT) for:
- Disposition categories: Fixed / By design / False positive / Acknowledged
- Reply templates
- Consensus flow (post reply → observe → decide)
- Bot agreement mechanics (per `review--bot-operations.md` § Agreement)
- Reviewer unavailable handling

### FSM context

This command runs in states **ChangesRequired** or **UnresolvedThreads**. Valid transitions: → CIPending (after push) → ReadyForReview or ReviewDone.

## Act

### 1. Classify and present findings

Present the classified list before proceeding with fixes.

### 2. Fix each P0/P1 finding

For each finding (priority order):
1. Read the file and surrounding context (±10 lines)
2. Determine validity
3. Apply fix or note false positive rationale

### 3. Post disposition replies and seek consensus

Per `HS-REVIEW-RESOLVE` and `review--consensus-protocol.md`:

1. Post disposition reply on each thread (Fixed / By design / False positive / Acknowledged)
2. Trigger re-review (Step 5 below)
3. After re-review: check bot agreement
   - Bot auto-resolved → consensus confirmed
   - Bot confirmed → resolve thread
   - Bot objected → address and retry
   - Timeout with evidence → resolve with justification per `review--consensus-protocol.md` § Reviewer Unavailable (requires proof of unavailability + independent verification)
   - Timeout without evidence → escalate to user; do not resolve unilaterally
4. Verify: `reviews.threads_unresolved == 0`

### 4. Quality gate

```bash
make format-check
```

Fix any failures before committing.

### 5. Commit, push, and re-review

```bash
git add -A
git commit -m "fix(<scope>): address review feedback

Refs: #<issue>"
git push
```

Trigger CodeRabbit re-review (if budget remaining per `review--bot-operations.md` § CR Review Budget):

```bash
gh pr comment <PR> --body "@coderabbitai review"
```

**Fast path** (one-shot observation per `controls--observation-execution-boundary.md`):

```text
make evidence-pull-request PR=<N>   (one-shot, no sleep)
├── threads_unresolved == 0 AND review_concluded
│   → Skip delegation, proceed to pr-merge
└── threads_unresolved > 0 OR review_concluded == false
    → Delegate via delegation--review-wait.md (run_in_background: true, model: "fast")
    → STOP and re-enter next for state re-assessment
```

The one-shot check is not polling — it is a single evidence read with immediate branching. If CodeRabbit has already auto-resolved all threads (common for "Fixed" dispositions), delegation overhead is avoided.

### 6. Report

- Findings addressed: count by source and severity
- False positives: count with reasons
- Quality gate: pass/fail
- Next step: `pr-review` (re-assessment)

## Guard / Validation

- `HS-REVIEW-RESOLVE`: every thread gets disposition reply before resolve
- `required_conversation_resolution`: blocks merge until all threads resolved
- `pre-push` hook: differential checks before push
- CR review budget: max 2 reviews per PR

> **Observation boundary**: Observation commands MUST use `make evidence-*` targets (`HS-EVIDENCE-FIRST`). Execution commands use raw CLI. Polling MUST be delegated (`HS-NO-INLINE-POLL`). See `controls--observation-execution-boundary.md`.

> **Anti-pattern — judgment creep**: Disposition categories and consensus flow are defined in `review--consensus-protocol.md`. This procedure follows them — it does not reinvent them.

## Related

- `review--consensus-protocol.md` — disposition, consensus, resolve (SSOT)
- `review--bot-operations.md` — detection, timing, agreement mechanics
- `pr-review.md` — produces findings this command addresses
- `pr-merge.md` — next step after re-review confirms mergeable
