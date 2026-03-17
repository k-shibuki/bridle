# next

## Reads

- `controls--workflow-state-machine.md` (state catalog, transitions, priority rules)
- `subagent-policy.mdc` (delegation for blocking operations)
- `agent--delegation-decision.md` (template selection)

## Sense

1. Run `make evidence-workflow-position` for coarse state (git, issues, PRs, environment).
2. If `on_main == true` and `open_issues_count > 0`, also run `make evidence-issue` to evaluate Issue quality (test plan, acceptance criteria) for PreFlightReview vs ReadyToStart classification. If the user requested control-system scope or "252 and later", use `make evidence-issue SCOPE=control-system` (or `ISSUE_MIN=252`).
3. If a PR exists for the current branch, also run `make evidence-pull-request PR=<number>` for detailed CI, merge, and review signals (preferred over workflow-position fallback per `state-model.md` § Signal catalog).

If a background subagent was previously launched, check its transcript file per `subagent-policy.mdc` § Completion guarantee.

## Act

### 1. Classify state

Consult `controls--workflow-state-machine.md` for formal state definitions. When multiple states apply, follow § Priority Rules (EnvironmentIssue > CIFailed > DependentChainRebase > UnresolvedThreads > ChangesRequired > StaleBranches > others).

### 2. Route to action card

| FSM state | → Action card |
|-----------|--------------|
| NoWorkPlanned | `issue-create` |
| PreFlightReview | `issue-review` |
| ReadyToStart | `implement` |
| Implementing / ImplementationDone | `test-create` |
| TestsDone / QualityOK / TestsPass | `verify` |
| TestsPass (no uncommitted) | `commit` |
| Committed | `pr-create` |
| CIPending | Delegate via `delegation--ci-wait-only.md` |
| BotReviewPending | Delegate via `delegation--review-wait.md` |
| ReadyForReview | `pr-review` |
| ExceptionFlow | `pr-create` (exception path) |
| CIFailed | Fix inline, re-push, re-enter `next` |
| UnresolvedThreads / ChangesRequired | `review-fix` |
| ReviewDone | `pr-merge` |
| DependentChainRebase | `git rebase --onto` per `git--squash-merge-dependent-branch.md` |
| StaleBranches | Delete stale branches |
| CycleComplete | Post-cycle scan → `implement` |
| EnvironmentIssue | `doctor` |

### 3. Present proposal and execute

State the current state, proposed action card, and reason. On approval, read the action card and follow its steps. On completion, re-run Sense to re-assess state.

### 4. Delegation for blocking operations

When state is CIPending or BotReviewPending, delegate per `subagent-policy.mdc`. After delegation, run Two-Tier Gate (§ Productive work during delegation) using the evidence already collected.

## Output

- Current FSM state with evidence basis
- Proposed action card and reason
- Execution result (after card completes)

## Guard

- `HS-EVIDENCE-FIRST`: observation via `make evidence-*` only
- `HS-NO-INLINE-POLL`: delegate all waits > 10s to background subagents
- `HS-NO-SKIP`: execute every step; gate passage requires evidence
