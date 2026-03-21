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

**Orchestration (mandatory)** — Before executing any action card, follow `docs/agent-control/next-orchestration.md`: present the **full remaining path** through **Per-unit Definition of Done** and obtain **one** user approval per run.

**Per-unit DoD is not “merge only”** — The completion condition is the **full closure** in `docs/agent-control/next-orchestration.md` § Per-unit Definition of Done: **merge (when policy allows) → remote branch delete when safe → local tracking branch cleanup**. Post-approval execution **must continue through all three**; stopping after merge alone is **not** DoD.

**Multi-unit default** — If `evidence-workflow-position` shows **`pull_requests.open_count > 1`** OR **any actionable Issue without a corresponding open PR** (see `workflow--issue-selection.md`), you **must** run **`docs/agent-control/next-orchestration.md` Phase A** (build the ordered queue from evidence) and **not** silently reduce scope to “current branch’s PR only.” Single-unit path is for **one** clear unit **after** the queue is empty or the user explicitly narrows scope. When multiple PRs are open, still list **all** candidates in Phase A (order, deps, notes) before Phase B approval or single-unit carve-out.

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

- **Single active unit**: Per `next-orchestration.md` (Single active unit) — output the **ordered sequence** from current FSM state through **Per-unit Definition of Done** (including `pr-merge` and branch hygiene). Obtain **explicit approval once** for that full path and completion condition. Then execute cards in a loop until that DoD — **no** per-card re-approval. Do **not** define counter-based “N failures then escalate” stops.
- **Multi-unit batch**: Per `next-orchestration.md` **Phases A–C**. **Phase B** is the **only** batch-level user wait (approved unit list, order, same Per-unit Definition of Done per unit). **Phase C** runs autonomously until every approved unit completes — **no** per-card or per-unit re-approval after Phase B.

#### Post-approval execution contract (mandatory, non-negotiable)

After the user gives **explicit approval** for the full path (single-unit) or **Phase B** (batch), the agent **MUST** drive to **Per-unit Definition of Done** **without inserting any further user interaction that gates progress**. Treat this as a **continuous autonomous run**: refresh evidence, execute each routed action card in order, launch delegations for `CIPending` / `BotReviewPending`, fix and re-push on `CIFailed`, run `review-fix` / `pr-review` / `pr-merge`, then **remote branch delete and local tracking cleanup** as required — **step by step, to full closure** (merge + remote delete + local prune), in the same session when tooling allows.

**Forbidden after approval** (until **full** Per-unit Definition of Done — merge **and** branch hygiene — or a documented stop below):

- Asking whether to continue, which option to take, or “should I do X next” (including soft closers that function as a gate).
- Stopping with only a roadmap while DoD remains unmet, when the agent could still act.
- Substituting “tell the user to wait” for **delegation** where `subagent-policy.mdc` requires a background subagent.

**Allowed stops** (same as `next-orchestration.md`): **Hard Stops** in `agent-safety.mdc`, **genuine cannot proceed** with evidence (credentials, org enforcement, unrecoverable GitHub block), **proposal-only** runs where the user declared no execution up front, or **tooling/session limits** — in the last case, **resume the same approved path on the next turn without re-approval** (no new Phase B / no new single-unit approval gate).

Final user-visible output **after** DoD (or after an allowed stop): evidence-backed summary only — not a mid-flight permission request.

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
- **Steering**: After the user approves a full path (single-unit or Phase B batch), do not abandon it before the applicable **full** Definition of Done (merge **and** remote/local branch cleanup per `next-orchestration.md`) without user direction or a genuine policy/GitHub block (evidence-backed). No counter-based failure escalation. **Do not** use mid-run questions to replace execution; see **Post-approval execution contract** above.
