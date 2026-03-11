---
trigger: bot re-review, re-review decision, Codex re-review, CodeRabbit re-review, review re-trigger, supplementary review
---
# Bot Re-review

Re-review rules after `review-fix` pushes, finding integration, and
delegation to background subagents.

## Re-review after review-fix

Agent re-triggers CodeRabbit after every review-fix push (`review-fix` Step 5b).
Agent decides whether to also re-trigger Codex.

| Condition | CodeRabbit | Codex |
|-----------|-----------|-------|
| Any push to PR branch | Agent triggers `@coderabbitai review` | — |
| Push addresses a Codex-sourced finding | Agent triggers `@coderabbitai review` | Yes — `@codex review` |
| Push addresses only CodeRabbit/Cursor findings | Agent triggers `@coderabbitai review` | No |

## Finding Integration

All bot findings receive the **same evaluation** in `pr-review` —
assessed on technical merit with P0/P1 classification. Cursor and
bot reviewers have equal weight.

When both reviewers are triggered, deduplicate findings where both
flagged the same issue. Note the source for traceability.

## Delegation

Bot review wait is delegated to a background subagent (main agent must
not block). See `agent--delegation-templates.md`:

- **Template 4**: CI + Bot Review Wait (after `pr-create`)
- **Template 5**: Bot Review Wait Only (after `review-fix` re-trigger)

Both templates poll all triggered reviewers in parallel.

## Comment Response

See `review--comment-response.md` for reply format, resolve procedure,
and completeness invariant.

## Related

- `review--bot-trigger.md` — trigger rules and two-tier model
- `review--bot-detection.md` — output detection, state machine, polling
- `review--bot-timing.md` — timing, rate limits, recovery
- `review--comment-response.md` — reply format, resolve procedure
- `agent--delegation-templates.md` — Template 4/5 implement wait logic
- `.coderabbit.yaml` — CodeRabbit configuration
