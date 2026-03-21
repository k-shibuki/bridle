---
trigger: workflow state machine, FSM, finite state machine, state catalog, signal catalog, transition table, guard condition, state classification, tie-break, workflow position mapping, priority rules, constraint violation, intervention state, evidence-to-signal
---
# Workflow State Machine

Formal FSM specification for the AI agent workflow. This atom is the
**Orient** component — it defines states, signals, transitions, and
guards. `make evidence-workflow-position` returns the primary FSM input
(structured evidence). State classification is performed by `next` using
this evidence, not by the evidence target itself.

Canonical specification: `docs/agent-control/state-model.md`.

## State Categories (21 states)

Full state catalog with entry conditions is in `state-model.md`
§ State catalog. States are classified into 5 categories:

- **Progress** (normal forward movement): ReadyToStart, Implementing,
  ImplementationDone, TestsDone, QualityOK, TestsPass,
  Committed, CycleComplete, ExceptionFlow
- **Waiting** (blocked on external process — delegate to subagent):
  CIPending, BotReviewPending
- **Intervention** (agent action required): CIFailed,
  UnresolvedThreads, ChangesRequired, DependentChainRebase,
  EnvironmentIssue
- **Maintenance** (housekeeping): NoWorkPlanned, PreFlightReview,
  StaleBranches
- **Terminal** (ready for final action): ReviewDone

## Key Paths

- **Happy path**: ReadyToStart → Implementing → ImplementationDone →
  TestsDone → QualityOK → TestsPass → Committed →
  CIPending → BotReviewPending → ReadyForReview → ReviewDone →
  CycleComplete
- **CI failure loop**: CIPending → CIFailed → (fix, push) → CIPending
- **Review loop**: ReadyForReview → ChangesRequired → (fix, push) →
  CIPending → ...
- **Thread resolution**: UnresolvedThreads → (review-fix) →
  ReadyForReview (if `review_concluded == false`) or ReviewDone
  (if `review_concluded`, e.g. approved review, or bot-only path with `bot_review_completed` and all threads resolved). `RATE_LIMITED` / `TIMED_OUT` on a required bot yield `bot_review_failed` and `review_concluded == false` until an agent review path applies — see `state-model.md` § Review signals.

## Priority Rules (Tie-Break)

When multiple states apply simultaneously (highest priority first):

1. EnvironmentIssue — nothing works without healthy environment
2. CIFailed — failing CI blocks all progress
3. DependentChainRebase — merge conflicts block merge
4. UnresolvedThreads — unresolved threads block merge
5. ChangesRequired — review findings need addressing
6. StaleBranches — housekeeping, can be deferred
7. All other states — follow normal transition order

## State Classification

- **Intermediate** (CIPending, BotReviewPending): external process in
  progress, no agent action needed. Delegate to background subagents.
- **Constraint-violation** (CIFailed, UnresolvedThreads,
  ChangesRequired, DependentChainRebase, EnvironmentIssue): constraint
  violated, agent must take corrective action.

## Signal Sources

All signals derive from evidence targets. See `state-model.md`
§ Evidence-to-signal mapping for the complete table.

Key targets: `evidence-workflow-position` (git, issues, PRs,
environment, procedure context), `evidence-pull-request` (CI, merge,
reviews), `evidence-issue` (dependency graph),
`evidence-environment` (health).

## Guard Conditions

Guards map to Hard Stops in `agent-safety.mdc`. See `state-model.md`
§ Guard conditions for the full table.

## Related

- `docs/agent-control/state-model.md` — canonical specification
- `evidence-workflow-position` — primary FSM evidence input
- `agent-safety.mdc` — Hard Stop definitions
