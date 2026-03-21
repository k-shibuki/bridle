# next

## Reads

- `docs/agent-control/state-model.md` (FSM definitions, signal catalog)
- `docs/agent-control/next-orchestration.md` (full-path proposal, single approval, per-unit DoD through merge/cleanup; multi-unit Phases A–C)
- `.cursor/knowledge/controls--workflow-state-machine.md` (state catalog, transitions, priority rules)
- `subagent-policy.mdc` (delegation for blocking operations)
- `agent--delegation-decision.md` (template selection)

## Sense

1. Run `make evidence-workflow-position` for coarse state (git, issues, PRs, environment).
2. If `on_main == true` and `open_issues_count > 0`, also run `make evidence-issue` to evaluate Issue quality (test plan, acceptance criteria) for PreFlightReview vs ReadyToStart classification. If the user requested control-system scope or "252 and later", use `make evidence-issue SCOPE=control-system` (or `ISSUE_MIN=252`).
3. If a PR exists for the current branch, also run `make evidence-pull-request PR=<number>` for detailed CI, merge, and review signals (preferred over workflow-position fallback per `state-model.md` § Signal catalog). For a single aggregate (`routing.effective_state_id`, `auto_merge_readiness` on the embedded PR), use `make evidence-fsm` (`docs/agent-control/evidence-schema.md` Target 4b).

**Orchestration (mandatory)** — Before executing any action card, follow `docs/agent-control/next-orchestration.md`: present the **full remaining path** through **Per-unit Definition of Done** (merge, remote branch delete, local tracking cleanup — not only the immediate routed card) and obtain **one** user approval per run. When **multiple work units** are in scope (several open PRs and/or actionable Issues without PRs), run **Phase A** of that document for the batch queue before the single-unit path.

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

### 3. Proposal, approval, execution

- **Single active unit**: Per `next-orchestration.md` § **Single active unit** — output the **ordered sequence** from current FSM state through **Per-unit Definition of Done** (including `pr-merge` and branch hygiene). Obtain **explicit approval once** for that full path and completion condition. Then execute cards in a loop until that DoD — **no** per-card re-approval. Do **not** define counter-based “N failures then escalate” stops.
- **Multi-unit batch**: Per `next-orchestration.md` **Phases A–C**. **Phase B** is the **only** batch-level user wait (approved unit list, order, same Per-unit Definition of Done per unit). **Phase C** runs autonomously until every approved unit completes — **no** per-card or per-unit re-approval after Phase B.

### 4. Delegation for blocking operations

When state is CIPending or BotReviewPending, delegate per `subagent-policy.mdc`. After delegation, run Two-Tier Gate (§ Productive work during delegation) using the evidence already collected.

## Output

- Current FSM state with evidence basis
- **Full-path proposal**: ordered remainder through **Per-unit Definition of Done** (`next-orchestration.md`), not only the first routed card; include merge, remote delete, local tracking cleanup in the narrative
- Approval captured (or proposal-only if user requested)
- Execution result: progress toward DoD, merge outcomes, blockers with evidence

## Guard

- `HS-EVIDENCE-FIRST`: observation via `make evidence-*` only
- `HS-NO-INLINE-POLL`: delegate all waits > 10s to background subagents
- `HS-NO-SKIP`: execute every step; gate passage requires evidence
- **Steering**: After the user approves a full path (single-unit or Phase B batch), do not abandon it before the applicable Definition of Done without user direction or a genuine policy/GitHub block (evidence-backed). No counter-based failure escalation.
