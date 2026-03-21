# Next orchestration (single-unit path + multi-unit batch)

**SSOT** for `/next` **after** state classification: what to show the user before execution, **one** approval gate per run (scope, order where relevant, completion condition), and post-approval work through the **full per-unit loop** (through merge and branch cleanup — not only the immediate next action card).

**Not a Cursor slash command** — this file lives under `docs/agent-control/`. The invocable command is [`.cursor/commands/next.md`](../../.cursor/commands/next.md) only; it **delegates** here for proposal, approval, and execution semantics.

**Design alignment**: [`architecture.md`](architecture.md) § Procedure layer design — `next.md` keeps the **FSM → action card routing table**; this document holds **orchestration** (single-unit gate + Phases A–C for batches). The agent must **not** answer `/next` with only the first routed card while omitting merge, auto-merge, remote delete, and local tracking cleanup from the user-visible plan.

## Reads (before proposing)

- `docs/agent-control/state-model.md` — signals, priority rules
- `.cursor/knowledge/controls--workflow-state-machine.md` — state catalog pointer
- `.cursor/knowledge/workflow--issue-selection.md` — actionability, ranking, dependency ordering (batch queue)
- `subagent-policy.mdc` — CI/bot wait delegation, completion guarantee
- `agent--delegation-decision.md` — template selection, auto-merge guard

## Per-unit Definition of Done (completion condition text)

Use this **verbatim** (or point here by path) in every user-facing approval summary — **single-unit and batch**:

For the unit at hand, the agent runs the full loop:

**Branch creation → implementation → review → review consensus complete → review-fix as needed → consensus on fixes complete → CI green with auto-merge allowed → auto-merge → remote branch deleted when safe → local tracking branch cleanup.**

**Hard boundary (agents):** “DoD” and “post-approval run until DoD” mean **through local tracking cleanup**, not “stop after `gh pr merge`.” If an agent treats merge as the end state, that is a **misread** of this section.

**Single-unit run complete** when this loop is finished for that unit. **Batch complete** when every approved unit has finished this loop in approved order.

Concrete gates (project SSOT): consensus and `auto_merge_readiness.safe_to_enable` (`HS-MERGE-CONSENSUS`), CI success (`HS-CI-MERGE`), merge and cleanup per `pr-merge.md`, `controls--merge-invariants.md`, `git--quick-recovery.md`.

## Single active unit — proposal + one approval (no batch)

When **one** clear work unit is active (typical: one checked-out branch for one Issue/PR path, and no multi-unit batch requested):

1. **Classify** FSM state from Evidence **after** completing `next.md` § Sense **Before the approval gate** (includes **mandatory** `make evidence-fsm`). Determine the **immediate** routed action card from `next.md` § Act (do not duplicate the table here).
2. **Plan (user-visible)** — Do **not** stop at “next card = X.” Trace **forward** from the current state along the routing table through **Per-unit Definition of Done**: list the **sequence of cards and waits** you expect (e.g. `test-create` → `verify` → `commit` → `pr-create` → … → `pr-merge`, including delegated CI/bot waits, rebase/conflict handling if evidence suggests it). State how **lightweight** evidence (workflow position, per-PR) and **aggregate** `evidence-fsm` support the plan. Note gaps (“PR not opened yet”, “unknown until review”) honestly; still show **merge + remote delete + local tracking cleanup** as explicit end states.
3. **Approval gate** — Present **once**: (a) unit identity (Issue # / PR # / branch), (b) the **ordered remainder** from current state through Per-unit Definition of Done, (c) the completion condition (Per-unit Definition of Done section above). Obtain **explicit user approval** to execute through that completion condition. **No per-card re-approval** after this gate (Hard Stops and genuine blocks excepted).
4. **Execute** — Run **post-approval** Sense (`next.md` § Sense **After approval**), classify → route → execute cards in a loop until Per-unit Definition of Done for this unit, then stop with evidence-backed summary. After **CI/bot delegation** returns, use the **mandatory** refresh list in `next.md` § Act (includes `make evidence-fsm`).

**Post-approval autonomy (mandatory)** — From step 4 onward, the agent **must not** prompt the user for permission, choice, or continuation between action cards or between delegation cycles. Execution is **strictly step-by-step and self-driven** through the approved sequence until DoD or an allowed stop. **Prohibited**: rhetorical “want me to…?”, optional follow-ups that block progress, or ending the turn with questions instead of delegating waits. **Required**: delegate `CIPending` / `BotReviewPending` per `subagent-policy.mdc` (**foreground** Tier 1 default for one unit — see `next.md` § Act · CI and bot wait recipe). When the subagent returns, immediately re-run Sense and the next routed card — do not treat “CI is slow” as a stop. On **tooling/session limits** only (narrow definition in Phase C below — **Tooling/session limits** and **Stops**), **resume the same approved path** next turn without re-opening step 3.

If the user asked **proposal only**, they must say so; otherwise default is execute after approval.

## Phase A — Propose (evidence-backed, multi-unit batch)

1. Run `make evidence-workflow-position` (required).
2. If `on_main == true` and `open_issues_count > 0`, run `make evidence-issue` (use `SCOPE=control-system` or `ISSUE_MIN=252` when the user requested that scope).
3. For each open PR that may need merge/review detail, run `make evidence-pull-request PR=<N>` as needed.
4. Run `make evidence-fsm` **once** (mandatory before Phase B — same aggregate contract as `next.md` § Sense **Before the approval gate** step 4).
5. **Build the work queue**:
   - Each **open PR** is one candidate unit (head branch + PR number).
   - Add **actionable Issues without an open PR** per `workflow--issue-selection.md` (ranking, `blocked_by`, parent Epic rules).
   - Respect **dependency order** (blocked issues after blockers; dependent PR chains per `git--squash-merge-dependent-branch.md`).
   - List **non-actionable** items separately with reason (blocked, missing test plan / acceptance criteria, parent-only Epic).
6. **WIP / dirty tree**: Before Phase C, the agent MUST resolve conflicts with branch switching — **stash**, **commit**, or **explicit user direction** on current-branch uncommitted work. Do not silently discard work.

**Output of Phase A**: A table — columns at minimum: unit id (PR # or Issue #), branch (if PR), title, suggested order, notes (blocked / deps). Include **§ Per-unit Definition of Done** verbatim (or by reference) and state that the batch completes when **each** unit has completed that loop in order.

## Phase B — Single approval gate (only user wait, multi-unit)

Present **once** to the user:

1. **Scope** — ordered list of units to process in this run.
2. **Order** — explicit sequence (dependency-respecting).
3. **Completion condition** — § Per-unit Definition of Done for **each** unit; batch done when all units have finished in order.

Obtain **explicit approval** (e.g. user confirms order, edits the list, or says to proceed as proposed). **No second approval** between units or between action cards after this gate. **No user prompts** that gate progress during Phase C (same contract as single-unit step 4 post-approval autonomy).

If the user wants **proposal only** (no execution), they must say so explicitly; default `next` flow assumes execution after approval.

## Phase C — Execute (after approval; autonomous until batch DoD)

For **each unit** in order:

1. `git fetch` / checkout the correct branch (PR head or new branch for Issue implementation).
2. Re-run **Sense** for **this** branch per `next.md` § Sense **After approval** (and after delegation returns, the CI/bot recipe refresh list including `make evidence-fsm`).
3. **Classify** FSM state; **route** using the **routing table in `next.md` § Act** (SSOT — do not duplicate the table here).
4. Execute the routed **action card** (`implement`, `verify`, `commit`, `pr-create`, `pr-review`, `review-fix`, `pr-merge`, …) including its `## Reads`.
5. **CIPending** / **BotReviewPending**: delegate per `subagent-policy.mdc` and `next.md` § Act · CI and bot wait recipe — **foreground** Tier 1 default for one unit; **no inline polling** in the main agent (`HS-NO-INLINE-POLL`).
6. Repeat steps 2–5 until **this unit** satisfies **§ Per-unit Definition of Done**.
7. Sync **`main`**, delete merged remote branch when safe, clean up local tracking refs; then **next unit**.

**Steering**: Do **not** truncate the approved queue because of conversation length or subjective “session scope.” If stopped by **tooling/session limits** (see below), **resume the same approved queue** on the next turn without re-opening Phase B unless the user revokes or changes scope. The same applies to a **single-unit** approved path: resume toward **Per-unit Definition of Done** without asking for a new approval each card. **Never** substitute mid-run user questions for continuing execution when the approved path still applies.

**Tooling/session limits** (narrow definition — **not** an excuse to exit a wait):

- Cursor chat **session ended** or **tooling unavailable** (e.g. cannot invoke Task/subagent or run `make evidence-*`).
- **Context length** or platform limit makes further tool use impossible in this session.

**Not** tooling limits: long CI or bot review duration, “this is taking a while,” or reluctance to block on a **foreground** Tier 1 subagent. For those, keep the subagent running until it returns, then continue.

**Stops** (no retry counters, no “N failures” escalation):

- **Hard Stops** in `agent-safety.mdc` (e.g. cannot merge without CI green; no `--admin` merge).
- **Genuine cannot proceed** — missing credentials, org settings, or GitHub-enforced block — report with **evidence** and stop; do not invent counter-based escalation.
- **Tooling/session limits** — as defined above only; then resume the same path next turn without a new approval gate.

## Parallelism

Independent **wait** states (multiple PRs waiting on CI/bot) may use **one background subagent per PR** (`run_in_background: true`) per `subagent-policy.mdc` § Multiple concurrent subagents. A **single** PR wait uses a **foreground** Tier 1 subagent instead. **Implementation** stays **one unit at a time** — no interleaved unrelated edits across units.

## What not to put here

- **Counter-based** “escalate after N failed recovery attempts” — not operational; do not document or implement.
- A duplicate **FSM → action card** table — lives only in `next.md`.

## Related

- `workflow-policy.mdc` — 1 Issue ≈ 1 PR, review/merge separation
- `docs/agent-control/state-model.md` — FSM definitions
- `.cursor/knowledge/git--squash-merge-dependent-branch.md` — dependent PR rebase
