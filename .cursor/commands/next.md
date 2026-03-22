# next

## Reads

- `docs/agent-control/state-model.md` (FSM definitions, signal catalog)
- `docs/agent-control/next-orchestration.md` (full-path proposal, single approval, per-unit DoD through merge/cleanup; multi-unit Phases A–C)
- `.cursor/knowledge/controls--workflow-state-machine.md` (state catalog, transitions, priority rules)
- `subagent-policy.mdc` (delegation for blocking operations)
- `agent--delegation-decision.md` (template selection)

## Sense

### Before the approval gate (mandatory aggregate)

Run **once** before presenting the full-path proposal in `next-orchestration.md` (single-unit steps 2–3, or Phase A output → Phase B):

1. Run `make evidence-workflow-position` for coarse state (git, issues, PRs, environment).
2. If `on_main == true` and `open_issues_count > 0`, also run `make evidence-issue` to evaluate Issue quality (test plan, acceptance criteria) for PreFlightReview vs ReadyToStart classification. If the user requested control-system scope or "252 and later", use `make evidence-issue SCOPE=control-system` (or `ISSUE_MIN=252`).
3. If a PR exists for the current branch, also run `make evidence-pull-request PR=<number>` for detailed CI, merge, and review signals (preferred over workflow-position fallback per `state-model.md` § Signal catalog). **Before routing** `BotReviewPending`, `UnresolvedThreads`, `ReadyForReview`, or `ReviewDone`, correlate that payload: `reviews.threads_unresolved`, `reviews.review_threads_truncated`, required `reviews.bot_* .findings_count`, `reviews.diagnostics` (`required_bot_findings_outstanding`, `non_thread_bot_findings_outstanding`, `rereview_response_pending`), `reviews.re_review_signal` (including `trigger_comment_log` when trigger timing is unclear), and `auto_merge_readiness.blockers`. Do not treat bot wait as done from `bot_review_pending == false` alone while findings, truncation, unresolved threads, or re-review pending still imply work per FSM.
4. Run `make evidence-fsm` **(mandatory)** — unified `routing.effective_state_id`, embedded PR `auto_merge_readiness` when a PR exists, merged environment errors + workflow position (`docs/agent-control/evidence-schema.md` Target 4b). The proposal must treat this as the **aggregate** orientation layer alongside steps 1–3.

**Tier B:** Before `implement`, `test-create`, or `verify`, if `environment.container_running == false` (from step 1 or the fsm payload), run `make evidence-environment` for detailed checks.

### After approval (routine refresh)

During the post-approval execution loop, refresh evidence **without** running `make evidence-fsm` on every card unless classification is unclear or a procedure step below requires it. Typically use `make evidence-workflow-position` and `make evidence-pull-request PR=<number>` when a PR exists. After each `evidence-pull-request` refresh affecting review state, apply the same **PR review correlation** checklist as in Sense step 3 before choosing `delegation--review-wait.md` vs `pr-review` / `review-fix` / `pr-merge`.

**Orchestration (mandatory)** — Before executing any action card, follow `docs/agent-control/next-orchestration.md`: present the **full remaining path** through **Per-unit Definition of Done** and obtain **one** user approval per run.

**Per-unit DoD is not “merge only”** — The completion condition is the **full closure** in `docs/agent-control/next-orchestration.md` § Per-unit Definition of Done: **merge (when policy allows) → remote branch delete when safe → local tracking branch cleanup**. Post-approval execution **must continue through all three**; stopping after merge alone is **not** DoD.

**Multi-unit default** — If `evidence-workflow-position` shows **`pull_requests.open_count > 1`** OR **any actionable Issue without a corresponding open PR** (see `workflow--issue-selection.md`), you **must** run **`docs/agent-control/next-orchestration.md` Phase A** (build the ordered queue from evidence) and **not** silently reduce scope to “current branch’s PR only.” Single-unit path is for **one** clear unit **after** the queue is empty or the user explicitly narrows scope. When multiple PRs are open, still list **all** candidates in Phase A (order, deps, notes) before Phase B approval or single-unit carve-out.

If a **background** subagent was previously launched (`run_in_background: true`), check its transcript file per `subagent-policy.mdc` § Completion guarantee. Foreground Tier 1 tasks do not use transcript monitoring — the Task return is the handoff.

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
| CIPending | Tier 1 subagent + recipe below (`delegation--ci-wait-only.md`) |
| BotReviewPending | Tier 1 subagent + recipe below (`delegation--review-wait.md`) |
| ReadyForReview | `pr-review` |
| ExceptionFlow | `pr-create` (exception path) |
| CIFailed | Fix inline, re-push, re-enter `next` |
| UnresolvedThreads / ChangesRequired | `review-fix` |
| ReviewDone | `pr-merge` |
| DependentChainRebase | `git rebase --onto` per `git--squash-merge-dependent-branch.md` |
| StaleBranches | Delete stale branches |
| CycleComplete | Post-cycle scan → `implement` |
| EnvironmentIssue | `doctor` |

#### CI and bot wait recipe (`CIPending` / `BotReviewPending`)

Use a **foreground** Tier 1 subagent by default (**omit** `run_in_background`) so the Task blocks until the wait completes — see `subagent-policy.mdc` § Subagent configuration and prompts. Template: `.cursor/templates/delegation--ci-wait-only.md` or `delegation--review-wait.md`; selection: `agent--delegation-decision.md`.

1. Launch the subagent with the appropriate template and PR number.
2. When the subagent returns, run Sense again: `make evidence-fsm`, then `make evidence-pull-request PR=<N>` and/or `make evidence-workflow-position` as needed, then **re-classify** from § Route to action card — **do not** end the turn while still waiting. After `evidence-pull-request`, confirm `review_threads_truncated`, `threads_unresolved`, `reviews.diagnostics.required_bot_findings_outstanding`, and `re_review_signal.cr_response_pending_after_latest_trigger` jointly match the new FSM state (avoid exiting `BotReviewPending` on a single field).
3. If evidence shows **CIFailed** → fix inline, push, re-enter this recipe (post-approval path; no new user approval).
4. On CI success, continue to the next routed card (e.g. `ReadyForReview` → `pr-review`).

**Multi-unit / N concurrent PR waits**: use `run_in_background: true` per PR and `subagent-policy.mdc` § Completion guarantee.

### 3. Proposal, approval, execution

- **Single active unit**: Per `next-orchestration.md` (Single active unit) — output the **ordered sequence** from current FSM state through **Per-unit Definition of Done** (including `pr-merge` and branch hygiene). Obtain **explicit approval once** for that full path and completion condition. Then execute cards in a loop until that DoD — **no** per-card re-approval. Do **not** define counter-based “N failures then escalate” stops.
- **Multi-unit batch**: Per `next-orchestration.md` **Phases A–C**. **Phase B** is the **only** batch-level user wait (approved unit list, order, same Per-unit Definition of Done per unit). **Phase C** runs autonomously until every approved unit completes — **no** per-card or per-unit re-approval after Phase B.

#### Post-approval execution contract (mandatory, non-negotiable)

After the user gives **explicit approval** for the full path (single-unit) or **Phase B** (batch), the agent **MUST** drive to **Per-unit Definition of Done** **without inserting any further user interaction that gates progress**. Treat this as a **continuous autonomous run**: refresh evidence, execute each routed action card in order, launch delegations for `CIPending` / `BotReviewPending`, fix and re-push on `CIFailed`, run `review-fix` / `pr-review` / `pr-merge`, then **remote branch delete and local tracking cleanup** as required — **step by step, to full closure** (merge + remote delete + local prune), in the same session when tooling allows.

**Forbidden after approval** (until **full** Per-unit Definition of Done — merge **and** branch hygiene — or a documented stop below):

- Asking whether to continue, which option to take, or “should I do X next” (including soft closers that function as a gate).
- Stopping with only a roadmap while DoD remains unmet, when the agent could still act.
- Substituting “tell the user to wait” for **Tier 1 delegation** where `subagent-policy.mdc` requires a subagent (foreground or background).

**Allowed stops** (same as `next-orchestration.md`): **Hard Stops** in `agent-safety.mdc`, **genuine cannot proceed** with evidence (credentials, org enforcement, unrecoverable GitHub block), **proposal-only** runs where the user declared no execution up front, or **tooling/session limits** (narrow definition in `next-orchestration.md` — long CI/bot waits are **not** a tooling limit). In the last case, **resume the same approved path on the next turn without re-approval** (no new Phase B / no new single-unit approval gate).

Final user-visible output **after** DoD (or after an allowed stop): evidence-backed summary only — not a mid-flight permission request.

### 4. Delegation for blocking operations

When state is CIPending or BotReviewPending, follow § Act · CI and bot wait recipe and `subagent-policy.mdc`. After a **foreground** subagent returns, re-run Sense and continue the `/next` loop — **do not** open a transcript monitoring loop. After **background** subagents only, run Two-Tier Gate and § Completion guarantee.

## Output

- Current FSM state with evidence basis
- **Full-path proposal**: ordered remainder through **Per-unit Definition of Done** (`next-orchestration.md`), not only the first routed card; include merge, remote delete, local tracking cleanup in the narrative
- Approval captured (or proposal-only if user requested)
- Execution result: progress toward DoD, merge outcomes, blockers with evidence

## Guard

- `HS-EVIDENCE-FIRST`: observation via `make evidence-*` only
- `HS-NO-INLINE-POLL`: no inline `sleep`+poll in the main agent; use Tier 1 subagent (foreground default for one unit — `agent-safety.mdc`)
- `HS-NO-SKIP`: execute every step; gate passage requires evidence
- **Steering**: After the user approves a full path (single-unit or Phase B batch), do not abandon it before the applicable **full** Definition of Done (merge **and** remote/local branch cleanup per `next-orchestration.md`) without user direction or a genuine policy/GitHub block (evidence-backed). No counter-based failure escalation. **Do not** use mid-run questions to replace execution; see **Post-approval execution contract** above.
