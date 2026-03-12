# next

## Purpose

Determine the next action by observing the current workflow state and routing to the appropriate procedure. This is the meta-command that orchestrates all others.

## Sense

Run `make evidence-workflow-position` to get the structured workflow state.

If a background subagent was previously launched, check its transcript file per `subagent-policy.mdc` "Completion guarantee."

## Orient

### State classification

Consult `controls--workflow-state-machine.md` for formal state definitions. The evidence output maps to FSM states through the categories:

- **Progress**: normal forward movement → route to next procedure
- **Waiting**: blocked on external process → delegate to background subagent
- **Intervention**: agent action required → fix the constraint violation
- **Maintenance**: housekeeping → cleanup or create work
- **Terminal**: ready for final action → execute and complete cycle

### Routing table

| FSM state | Next command | Key evidence fields |
|-----------|-------------|-------------------|
| NoWorkPlanned | `issue-create` | `issues.open_count == 0` |
| PreFlightReview | `issue-review` | Open Issues not yet reviewed |
| ReadyToStart | `implement` | `git.on_main`, no uncommitted, actionable Issues |
| Implementing / ImplementationDone | `test-create` | On feature branch, R/ changes, no tests |
| TestsDone | `quality-check` | Tests exist, not quality-checked |
| QualityOK | `test-regression` | Quality OK, suite not run |
| TestsPass | `docs-discover` (Mode 2) | Tests pass, docs not reviewed |
| DocsOK | `commit` | Docs OK, uncommitted changes |
| Committed | `pr-create` | Committed, no PR |
| CIPending | Delegate via `delegation--ci-wait-only.md` (`run_in_background: true`, `model: "fast"`) | `pull_requests.open[].ci_status == "pending"` |
| BotReviewPending | Delegate via `delegation--review-wait.md` (`run_in_background: true`, `model: "fast"`) | Bot review not yet completed |
| ReadyForReview | `pr-review` | CI green, bot review terminal |
| ExceptionFlow | `pr-create` (exception path) | Hotfix or no-issue work |
| CIFailed | Fix inline, re-push | `ci_status == "failure"` |
| UnresolvedThreads | `review-fix` | `review_threads_unresolved > 0` |
| ReviewDone | `pr-merge` | Review concluded mergeable |
| ChangesRequired | `review-fix` | Review concluded changes_required |
| DependentChainRebase | `git rebase --onto` | `mergeable == "CONFLICTING"`, parent recently merged |
| StaleBranches | Delete stale branches | `git.stale_branches` non-empty |
| CycleComplete | Post-cycle scan → `implement` | PR merged, on main |
| EnvironmentIssue | `doctor` | `environment.doctor_healthy == false` |

### Priority rules (tie-break)

When multiple states apply, follow `controls--workflow-state-machine.md` § Priority Rules. Constraint-violation states always take precedence over progress states.

### Post-cycle signal scan

At CycleComplete, run a lightweight scan per `session-retro.md` § Quick Scan Mode. "No signals" is the normal result — proceed silently.

## Act

### 1. Present proposal

```text
## Next Action

### Current state
- Branch: `<branch>`
- Uncommitted changes: <yes/no>
- Open Issues: <count> (<actionable> actionable)
- Open PRs: <count> (CI: <status>)

### Proposed action: `<command-name>`
- Reason: <why>
- Target: <Issue/PR>

Proceed? [Y/n]
```

### 2. Execute on approval

1. Read `.cursor/commands/<command>.md`
2. Follow its steps exactly (`HS-NO-SKIP`)
3. On completion, re-run Sense to re-assess state
4. Continue until: user scope fulfilled, decision requires user judgment, or error persists after fix

### 3. Delegation for blocking operations

When state is CIPending or BotReviewPending, delegate per `subagent-policy.mdc` using templates from `.cursor/templates/delegation--*.md`. See `agent--delegation-decision.md` for the decision flowchart.

### 4. Parallel execution

When CI is pending and independent Issues exist, start the next Issue while CI completes:

```text
Issue A: ... → pr-create → CI pending
                              │
    ┌─────────────────────────┤
    │ Background subagent     │ Main agent
    │ poll CI → report        │ Issue B: implement → ...
    └─────────────────────────┤
                              │
    next re-assessment: CI green → pr-review → pr-merge
```

## Guard / Validation

- `pre-push` hook runs differential checks before every push (`HS-LOCAL-VERIFY`)
- All policies remain invariant after user approval (`HS-NO-SKIP`)
- Subagent delegation per `subagent-policy.mdc` for all blocking operations

> **Observation boundary**: Observation commands MUST use `make evidence-*` targets (`HS-EVIDENCE-FIRST`). Execution commands use raw CLI. Polling MUST be delegated (`HS-NO-INLINE-POLL`). See `controls--observation-execution-boundary.md`.

> **Anti-pattern — judgment creep**: If this procedure starts accumulating complex conditional logic, the logic belongs in Knowledge atoms or the FSM specification, not here.

## Related

- `controls--workflow-state-machine.md` — FSM state catalog, transitions, tie-break
- `agent--delegation-decision.md` — delegation flowchart
- `subagent-policy.mdc` — subagent delegation policy
- `session-retro.md` — post-cycle signal scan
