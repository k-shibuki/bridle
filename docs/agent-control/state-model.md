# FSM / State Model

## State catalog

Each state represents a distinct workflow position with a defined set
of available transitions.

| ID | State | Description | Entry condition |
|----|-------|-------------|-----------------|
| ST_NO_WORK | `NoWorkPlanned` | No open Issues exist | `open_issues_count == 0` |
| ST_PREFLIGHT | `PreFlightReview` | Issues exist but have not been reviewed for quality | `open_issues_count > 0 AND on_main AND no_uncommitted AND issues_require_preflight_review` |
| ST_READY | `ReadyToStart` | Actionable Issues exist, ready to implement | `open_issues_count > 0 AND on_main AND no_uncommitted AND issues_require_preflight_review == false` |
| ST_IMPL | `Implementing` | On feature branch, implementation in progress | `on_feature_branch AND workflow_phase == "implementing"` |
| ST_IMPL_DONE | `ImplementationDone` | Code written, tests not yet created | `on_feature_branch AND workflow_phase == "implementation_done"` |
| ST_TESTS_DONE | `TestsDone` | Tests created, quality not yet checked | `on_feature_branch AND workflow_phase == "tests_done"` |
| ST_QUALITY_OK | `QualityOK` | Quality gates passed, tests not run as full suite | `on_feature_branch AND workflow_phase == "quality_ok"` |
| ST_TESTS_PASS | `TestsPass` | Full test suite passed, ready to commit | `on_feature_branch AND workflow_phase == "tests_pass"` |
| ST_COMMITTED | `Committed` | All changes committed, no PR exists | `on_feature_branch AND no_uncommitted AND pr_exists_for_branch == false` |
| ST_CI_PENDING | `CIPending` | PR exists, CI still running | `pr_exists_for_branch AND ci_status == "pending"` |
| ST_CI_FAILED | `CIFailed` | PR exists, CI failed | `pr_exists_for_branch AND ci_status == "failure"` |
| ST_BOT_PENDING | `BotReviewPending` | CI green, waiting on required bot outcome or on a CodeRabbit pull review after the latest `@coderabbitai review` trigger | `pr_exists_for_branch AND ci_status == "success" AND (bot_review_pending OR rereview_response_pending)` — see `evidence-pull-request.reviews.diagnostics.rereview_response_pending` |
| ST_UNRESOLVED | `UnresolvedThreads` | Review threads exist that lack consensus | `pr_exists_for_branch AND review_threads_unresolved > 0` |
| ST_REVIEW_READY | `ReadyForReview` | CI green, bot phase settled, agent review needed | `pr_exists_for_branch AND ci_status == "success" AND bot_review_terminal AND review_threads_unresolved == 0 AND auto_merge_readiness.review_consensus_complete == false` |
| ST_CHANGES_REQ | `ChangesRequired` | Review complete, changes requested | `pr_exists_for_branch AND review_disposition == "changes_requested"` |
| ST_REVIEW_DONE | `ReviewDone` | Review complete, mergeable | `pr_exists_for_branch AND auto_merge_readiness.review_consensus_complete AND mergeable_status == "MERGEABLE"` |
| ST_REBASE | `DependentChainRebase` | Merge conflict from squash-merged parent PR | `pr_exists_for_branch AND mergeable_status == "CONFLICTING" AND parent_pr_recently_merged` |
| ST_STALE | `StaleBranches` | Local branches track deleted remotes | `stale_branches_count > 0` |
| ST_CYCLE_DONE | `CycleComplete` | PR merged, back on main | `on_main AND pr_just_merged` |
| ST_ENV_ISSUE | `EnvironmentIssue` | Development environment unhealthy | `evidence-environment.errors > 0` **or** `evidence-workflow-position.environment.container_running == false` (see `docs/agent-control/fsm/global-workflow.jq`) |
| ST_EXCEPTION | `ExceptionFlow` | Hotfix or no-issue exception needed | `on_main AND exception_issue_exists` |

**State classification**:

- **Progress states** (ST_READY–ST_COMMITTED, ST_CYCLE_DONE): normal forward movement through the workflow (DocsOK removed — doc review is a precondition of commit, not a separate state)
- **Waiting states** (ST_CI_PENDING, ST_BOT_PENDING): blocked on external process
- **Intervention states** (ST_CI_FAILED, ST_UNRESOLVED, ST_CHANGES_REQ, ST_REBASE): require agent action to resolve
- **Maintenance states** (ST_NO_WORK, ST_PREFLIGHT, ST_STALE, ST_ENV_ISSUE): housekeeping or setup
- **Terminal states** (ST_REVIEW_DONE): ready for final action (merge)

## Signal catalog

Signals are observable facts derived from Evidence targets plus minimal
procedure context for in-progress local work.

### Git signals

| Signal | Type | Source | Interpretation |
|--------|------|--------|---------------|
| `branch_name` | string | `evidence-workflow-position.git.branch` | Current branch name |
| `on_main` | boolean | derived | `branch_name == "main"` |
| `on_feature_branch` | boolean | derived | `branch_name != "main"` |
| `uncommitted_files` | integer | `evidence-workflow-position.git.uncommitted_files` | Count of modified/untracked files |
| `no_uncommitted` | boolean | derived | `uncommitted_files == 0` |
| `stale_branches` | string[] | `evidence-workflow-position.git.stale_branches` | Branches whose remote tracking ref is gone |
| `stale_branches_count` | integer | derived | Length of `stale_branches` |
| `commits_ahead` | integer | `evidence-workflow-position.git.commits_ahead_of_remote` | Commits ahead of remote |
| `stash_count` | integer | `evidence-workflow-position.git.stash_count` | Number of stash entries |

### GitHub signals

| Signal | Type | Source | Interpretation |
|--------|------|--------|---------------|
| `open_issues` | object[] | `evidence-workflow-position.issues.open` | Open Issues with metadata |
| `open_issues_count` | integer | `evidence-workflow-position.issues.open_count` | Count of open Issues |
| `open_prs` | object[] | `evidence-workflow-position.pull_requests.open` | Open PRs with metadata |
| `open_pr_for_branch` | object \| null | derived | PR matching current branch |
| `pr_exists_for_branch` | boolean | derived | `open_pr_for_branch != null` |
| `recently_merged_prs` | object[] | `evidence-workflow-position.pull_requests.recently_merged` | Recently merged PRs (last 5) |
| `issues_require_preflight_review` | boolean | `evidence-issue.issues[]` | Any open issue lacks required planning fields |
| `exception_issue_exists` | boolean | `evidence-issue.issues[].labels[]` | Hotfix/no-issue exception issue is selected |
| `parent_pr_recently_merged` | boolean | `evidence-workflow-position.pull_requests.recently_merged` | Parent PR in dependent chain merged recently |
| `pr_just_merged` | boolean | derived | Recently merged PR exists and current branch is `main` |

### CI signals

| Signal | Type | Source | Interpretation |
|--------|------|--------|---------------|
| `ci_status` | enum | `evidence-pull-request.ci.status` (preferred), fallback `evidence-workflow-position.pull_requests.open[].ci_status` | `"success"` \| `"failure"` \| `"pending"` \| `"no_checks"` |
| `ci_failed_jobs` | string[] | `evidence-pull-request.ci.checks[]` | Names of failed CI jobs |
| `mergeable_status` | enum | `evidence-pull-request.merge.mergeable` (preferred), fallback `evidence-workflow-position.pull_requests.open[].mergeable` | `"MERGEABLE"` \| `"CONFLICTING"` \| `"UNKNOWN"` |
| `merge_state_status` | enum | `evidence-pull-request.merge.merge_state_status` | `"CLEAN"` \| `"HAS_HOOKS"` \| `"BEHIND"` \| `"DIRTY"` \| `"BLOCKED"` \| `"UNKNOWN"` |

### Review signals

| Signal | Type | Source | Interpretation |
|--------|------|--------|---------------|
| `review_threads_total` | integer | `evidence-pull-request.reviews.threads_total` | Total review thread count |
| `review_threads_unresolved` | integer | `evidence-pull-request.reviews.threads_unresolved` | Unresolved thread count |
| `review_threads_truncated` | boolean | `evidence-pull-request.reviews.review_threads_truncated` | `reviewThreads(first:100)` has more pages — treat unresolved count as incomplete; merge consensus false while true |
| `required_bot_findings_outstanding` | boolean | `evidence-pull-request.reviews.diagnostics.required_bot_findings_outstanding` | Required bots still report `findings_count > 0` (includes body-only findings) |
| `non_thread_bot_findings_outstanding` | boolean | `evidence-pull-request.reviews.diagnostics.non_thread_bot_findings_outstanding` | Findings outstanding with zero unresolved threads (outside-diff / body findings) |
| `bot_coderabbit_status` | enum | `evidence-pull-request.reviews.bot_coderabbit.status` | `"COMPLETED"` \| `"COMPLETED_CLEAN"` \| `"COMPLETED_SILENT"` \| `"SKIPPED_CLEAN"` \| `"SKIPPED_BLOCKED"` \| `"RATE_LIMITED"` \| `"TIMED_OUT"` \| `"NOT_TRIGGERED"` \| `"PENDING"` \| `"REVIEW_INVALIDATED"` |
| `bot_codex_status` | enum | `evidence-pull-request.reviews.bot_codex.status` | `"COMPLETED"` \| `"COMPLETED_CLEAN"` \| `"SKIPPED_CLEAN"` \| `"SKIPPED_BLOCKED"` \| `"RATE_LIMITED"` \| `"TIMED_OUT"` \| `"NOT_TRIGGERED"` \| `"PENDING"` \| `"REVIEW_INVALIDATED"` |
| `bot_review_completed` | boolean | `evidence-pull-request.reviews.diagnostics.bot_review_completed` | All required bots in a **Reviewed** tier state; optional (`required: false`) bots may be `NOT_TRIGGERED` or Reviewed |
| `bot_review_failed` | boolean | `evidence-pull-request.reviews.diagnostics.bot_review_failed` | Any **required** bot is in **Failed** tier (`RATE_LIMITED`, `TIMED_OUT`, `SKIPPED_BLOCKED`) |
| `bot_review_terminal` | boolean | `evidence-pull-request.reviews.diagnostics.bot_review_terminal` | `bot_review_completed OR bot_review_failed` — polling may stop; **never** sufficient alone for merge consensus |
| `bot_review_pending` | boolean | `evidence-pull-request.reviews.diagnostics.bot_review_pending` | `NOT bot_review_terminal` — still waiting on a required bot outcome |
| `rereview_response_pending` | boolean | `evidence-pull-request.reviews.re_review_signal.cr_response_pending_after_latest_trigger` (same value as `reviews.diagnostics.rereview_response_pending`) | Latest PR issue comment requesting CodeRabbit re-review (`@coderabbitai` + `review`) is not yet followed by a completion after that comment (pull review, commit-status completion, or `skip_patterns` issue comment); `false` when `bot_coderabbit.status` is `SKIPPED_CLEAN` / `SKIPPED_BLOCKED` or `REVIEW_INVALIDATED` (`pull-request-readiness.jq` adds blocker `rereview_response_pending` and can route `BotReviewPending` even when `bot_review_pending` is false) |
| `review_disposition` | enum | `evidence-pull-request.reviews.disposition` | `"approved"` \| `"changes_requested"` \| `"pending"` |
| `review_consensus_complete` | boolean | `evidence-pull-request.auto_merge_readiness.review_consensus_complete` | Merge consensus: approved human review, or pending disposition with required bots reviewed, **zero required-bot `findings_count` total**, zero unresolved threads, **not** `review_threads_truncated`, and no pending re-review response (`rereview_response_pending`) |
| `safe_to_enable` | boolean | `evidence-pull-request.auto_merge_readiness.safe_to_enable` | Safe to enable auto-merge: consensus + CI + mergeable + merge state (see `docs/agent-control/fsm/pull-request-readiness.jq`) |

**Bot tier semantics** (declarative; recovery procedures live in delegation templates, not here):

| Tier | `bot_*_status` values | Meaning |
|------|------------------------|---------|
| **Reviewed** | `COMPLETED`, `COMPLETED_CLEAN`, `COMPLETED_SILENT`, `SKIPPED_CLEAN` | Bot produced a review for the current head, or policy marks a skip as terminal-clean (`skip_policy: terminal_clean` in `review-bots.json`) |
| **Failed** | `RATE_LIMITED`, `TIMED_OUT`, `SKIPPED_BLOCKED` | Bot could not complete a review, or policy marks a skip as blocking (`skip_policy: terminal_blocked`) |
| **In-progress** | `PENDING`, `NOT_TRIGGERED`, `REVIEW_INVALIDATED` | No valid Reviewed outcome for the current head (`REVIEW_INVALIDATED`: bot voided its run, e.g. head commit moved during review — re-trigger; `NOT_TRIGGERED` on a **required** bot still blocks `bot_review_completed`) |

### Environment signals

| Signal | Type | Source | Interpretation |
|--------|------|--------|---------------|
| `doctor_healthy` | boolean | `evidence-environment` | `errors == 0` (workflow position no longer mirrors doctor; use `make evidence-environment` or `make evidence-fsm`) |
| `errors` | integer | `evidence-environment.errors` | Critical issue count |
| `warnings` | integer | `evidence-environment.warnings` | Warning count |
| `container_running` | boolean | `evidence-workflow-position.environment.container_running` | Dev container status; when `false`, `routing.global_state_id` is `EnvironmentIssue` (same rule in `evidence-fsm` after env merge) |

### Procedure-context signals

| Signal | Type | Source | Interpretation |
|--------|------|--------|---------------|
| `workflow_phase` | enum \| null | `evidence-workflow-position.procedure_context.workflow_phase` | `"implementing"` \| `"implementation_done"` \| `"tests_done"` \| `"quality_ok"` \| `"tests_pass"` \| `null` |
| `workflow_phase_stale` | boolean | `evidence-workflow-position.procedure_context.stale` | Phase file branch mismatch or > 24h old |
| `selected_issue_number` | integer \| null | `evidence-workflow-position.procedure_context.issue_number` | Issue selected for current implementation cycle |

## Evidence-to-signal mapping

This table is the canonical mapping from evidence output fields to FSM
signals used in state conditions and transitions.

| Signal | Evidence target | Field path |
|--------|------------------|------------|
| `branch_name` | `evidence-workflow-position` | `git.branch` |
| `on_main` | `evidence-workflow-position` | `git.on_main` |
| `uncommitted_files` | `evidence-workflow-position` | `git.uncommitted_files` |
| `stale_branches` | `evidence-workflow-position` | `git.stale_branches` |
| `commits_ahead` | `evidence-workflow-position` | `git.commits_ahead_of_remote` |
| `stash_count` | `evidence-workflow-position` | `git.stash_count` |
| `open_issues` | `evidence-workflow-position` | `issues.open` |
| `open_issues_count` | `evidence-workflow-position` | `issues.open_count` |
| `open_prs` | `evidence-workflow-position` | `pull_requests.open` |
| `recently_merged_prs` | `evidence-workflow-position` | `pull_requests.recently_merged` |
| `ci_status` | `evidence-pull-request` | `ci.status` |
| `mergeable_status` | `evidence-pull-request` | `merge.mergeable` |
| `merge_state_status` | `evidence-pull-request` | `merge.merge_state_status` |
| `review_threads_total` | `evidence-pull-request` | `reviews.threads_total` |
| `review_threads_unresolved` | `evidence-pull-request` | `reviews.threads_unresolved` |
| `review_threads_truncated` | `evidence-pull-request` | `reviews.review_threads_truncated` |
| `required_bot_findings_outstanding` | `evidence-pull-request` | `reviews.diagnostics.required_bot_findings_outstanding` |
| `non_thread_bot_findings_outstanding` | `evidence-pull-request` | `reviews.diagnostics.non_thread_bot_findings_outstanding` |
| `bot_coderabbit_status` | `evidence-pull-request` | `reviews.bot_coderabbit.status` |
| `bot_codex_status` | `evidence-pull-request` | `reviews.bot_codex.status` |
| `bot_review_completed` | `evidence-pull-request` | `reviews.diagnostics.bot_review_completed` |
| `bot_review_failed` | `evidence-pull-request` | `reviews.diagnostics.bot_review_failed` |
| `bot_review_terminal` | `evidence-pull-request` | `reviews.diagnostics.bot_review_terminal` |
| `bot_review_pending` | `evidence-pull-request` | `reviews.diagnostics.bot_review_pending` |
| `rereview_response_pending` | `evidence-pull-request` | `reviews.re_review_signal.cr_response_pending_after_latest_trigger` |
| `review_consensus_complete` | `evidence-pull-request` | `auto_merge_readiness.review_consensus_complete` |
| `review_disposition` | `evidence-pull-request` | `reviews.disposition` |
| `doctor_healthy` | `evidence-environment` | `errors == 0` |
| `container_running` | `evidence-workflow-position` | `environment.container_running` |
| `errors` | `evidence-environment` | `errors` |
| `warnings` | `evidence-environment` | `warnings` |
| `issues_require_preflight_review` | `evidence-issue` | `issues[].has_test_plan`, `issues[].has_acceptance_criteria` |
| `exception_issue_exists` | `evidence-issue` | `issues[].labels[]` |
| `workflow_phase` | `evidence-workflow-position` | `procedure_context.workflow_phase` |
| `workflow_phase_stale` | `evidence-workflow-position` | `procedure_context.stale` |
| `selected_issue_number` | `evidence-workflow-position` | `procedure_context.issue_number` |

## Transition table

Transitions define which state changes are valid. `Signal condition`
contains machine-evaluable expressions. `Trigger event` is optional and
captures explicit user/agent actions.

| From | Signal condition | Trigger event | To | Action |
|------|------------------|---------------|----|--------|
| ST_NO_WORK | `open_issues_count == 0` | none | ST_NO_WORK | `issue-create` |
| ST_PREFLIGHT | `issues_require_preflight_review == false` | `issue-review` completed | ST_READY | Continue workflow |
| ST_READY | `selected_issue_number != null` | Issue selected | ST_IMPL | `implement` (branch created) |
| ST_IMPL | `workflow_phase == "implementation_done"` | Implement step complete | ST_IMPL_DONE | Continue workflow |
| ST_IMPL_DONE | `workflow_phase == "tests_done"` | `test-create` completed | ST_TESTS_DONE | Continue workflow |
| ST_TESTS_DONE | `workflow_phase == "quality_ok"` | `verify` completed (format + lint + R CMD check) | ST_QUALITY_OK | Continue workflow |
| ST_QUALITY_OK | `workflow_phase == "tests_pass"` | `verify` completed (full test suite + coverage) | ST_TESTS_PASS | Continue workflow |
| ST_TESTS_PASS | `no_uncommitted AND pr_exists_for_branch == false` | `commit` completed | ST_COMMITTED | Continue workflow |
| ST_COMMITTED | `pr_exists_for_branch` | `pr-create` completed | ST_CI_PENDING | CI + bot review start |
| ST_CI_PENDING | `ci_status == "success"` | none | ST_BOT_PENDING | Wait for bot terminal state |
| ST_CI_PENDING | `ci_status == "failure"` | none | ST_CI_FAILED | Diagnose and fix |
| ST_CI_FAILED | `ci_status == "pending"` | fix pushed | ST_CI_PENDING | Re-enter CI pending |
| ST_BOT_PENDING | `bot_review_completed AND review_consensus_complete` | none | ST_REVIEW_DONE | Bot-only review concluded with no findings |
| ST_BOT_PENDING | `bot_review_completed AND NOT review_consensus_complete AND review_threads_unresolved > 0` | none | ST_UNRESOLVED | Bot findings need addressing |
| ST_BOT_PENDING | `bot_review_completed AND NOT review_consensus_complete AND review_threads_unresolved == 0` | none | ST_REVIEW_READY | Ready for human/agent review |
| ST_BOT_PENDING | `bot_review_failed` | none | ST_REVIEW_READY | Bot could not review — agent `pr-review` (recovery is procedural; see delegation templates) |
| ST_UNRESOLVED | `review_threads_unresolved == 0 AND review_consensus_complete == false` | `review-fix` completed | ST_REVIEW_READY | Ready for review |
| ST_UNRESOLVED | `review_threads_unresolved == 0 AND review_consensus_complete` | `review-fix` completed | ST_REVIEW_DONE | Mergeable review state |
| ST_REVIEW_READY | `review_consensus_complete` | `pr-review` completed | ST_REVIEW_DONE | Ready to merge |
| ST_REVIEW_READY | `review_disposition == "changes_requested"` | `pr-review` completed | ST_CHANGES_REQ | Fix required |
| ST_CHANGES_REQ | `ci_status == "pending"` | fix pushed | ST_CI_PENDING | Re-enter CI pending |
| ST_REVIEW_DONE | `mergeable_status == "MERGEABLE"` | `pr-merge` completed | ST_CYCLE_DONE | Cycle complete |
| ST_REBASE | `ci_status == "pending"` | rebase complete and pushed | ST_CI_PENDING | Re-enter CI pending |
| ST_STALE | `stale_branches_count == 0 AND open_issues_count > 0` | cleanup completed | ST_READY | Resume implementation |
| ST_STALE | `stale_branches_count == 0 AND open_issues_count == 0` | cleanup completed | ST_NO_WORK | No work planned |
| ST_CYCLE_DONE | `open_issues_count > 0` | none | ST_READY | Start next Issue |
| ST_CYCLE_DONE | `open_issues_count == 0` | none | ST_NO_WORK | All work complete |
| ST_ENV_ISSUE | `evidence-environment.errors == 0` **and** dev container running | environment fixed | ST_READY or ST_NO_WORK | `doctor` / `make container-start` then reassess |
| ST_EXCEPTION | `exception_issue_exists` | exception flow approved | ST_COMMITTED | `implement` → `pr-create` |

## Guard conditions

Guards are transitions that are **prohibited** regardless of other
conditions. They correspond to Hard Stops in `agent-safety.mdc`.

| Guard ID | Prohibited transition | Enforcement |
|----------|-----------------------|-------------|
| `HS-CI-MERGE` | ST_REVIEW_DONE → ST_CYCLE_DONE when `ci_status != "success"` | GitHub Branch Protection |
| `HS-CI-MERGE(a)` | Any merge using `--admin` flag | Agent self-policing |
| `HS-CI-MERGE(b)` | Amend + force-push in PR flow | Agent self-policing |
| `HS-LOCAL-VERIFY` | ST_COMMITTED → ST_CI_PENDING without pre-push verification | `pre-push` Git hook |
| `HS-NO-SKIP` | Any state skip (e.g., ST_IMPL_DONE → ST_COMMITTED) | Partial: `pr-policy.yaml` DoD check |
| `HS-PR-TEMPLATE` | ST_COMMITTED → ST_CI_PENDING without full PR template | `pr-policy.yaml` CI check |
| `HS-NO-DISMISS` | Ignoring quality gate errors | Agent self-policing |
| `HS-NOLINT` | Adding `# nolint` without knowledge consultation | `pre-commit` hook (format) + agent self-policing (consultation) |
| `HS-PR-BASE` | ST_COMMITTED → ST_CI_PENDING with `--base feat/<branch>` | `pr-policy.yaml` CI check |
| `HS-REVIEW-RESOLVE` | ST_UNRESOLVED → ST_REVIEW_DONE without per-thread consensus | GitHub Branch Protection `required_conversation_resolution` |
| `HS-MERGE-CONSENSUS` | Merge or auto-merge when `auto_merge_readiness.safe_to_enable != true` | Agent self-policing |

## Error states and recovery

| Error state | Detection | Recovery path |
|-------------|-----------|---------------|
| CI failure (ST_CI_FAILED) | `ci_status == "failure"` | Diagnose (`ci--failure-triage.md`), fix, re-push → ST_CI_PENDING |
| Merge conflict (ST_REBASE) | `mergeable_status == "CONFLICTING"` + parent PR merged | `git rebase --onto` (`git--squash-merge-dependent-branch.md`), force-push → ST_CI_PENDING |
| Bot rate limited | `bot_*_status == "RATE_LIMITED"` | Parse wait time, sleep, re-trigger → ST_BOT_PENDING |
| Bot timed out | `bot_*_status == "TIMED_OUT"` | Report, proceed with available evidence → ST_REVIEW_READY |
| Environment broken (ST_ENV_ISSUE) | `evidence-environment.errors > 0` **or** dev container not running | `make container-start` / `make container-build` / `make package-restore` / `make doctor` per action card |
| Format-lint loop | styler and lintr disagree | `lint--styler-lintr-conflict.md` |
| Pre-push rejection | Hook fails | Fix locally, re-attempt push |
| `check-policy` failure | PR body missing sections | Edit PR body directly (no commit needed) |

## Priority rules

When multiple states could apply simultaneously, use this precedence
(highest first):

1. **ST_ENV_ISSUE** (EnvironmentIssue) — nothing works without a healthy environment
2. **ST_CI_FAILED** (CIFailed) — failing CI blocks all PR progress
3. **ST_REBASE** (DependentChainRebase) — merge conflicts block merge
4. **ST_UNRESOLVED** (UnresolvedThreads) — unresolved threads block merge
5. **ST_CHANGES_REQ** (ChangesRequired) — review findings need addressing
6. **ST_STALE** (StaleBranches) — cleanup, can be done during housekeeping
7. **All other states** — follow normal transition order

## Intermediate states vs constraint-violation states

- **Intermediate states** (ST_IMPL, ST_CI_PENDING, ST_BOT_PENDING): the
  workflow is progressing normally but an external process has not
  completed. No agent action needed beyond monitoring.
- **Constraint-violation states** (ST_CI_FAILED, ST_UNRESOLVED,
  ST_CHANGES_REQ, ST_REBASE, ST_ENV_ISSUE): a constraint is violated
  and the agent must take corrective action before the workflow can
  proceed.

The distinction matters for delegation: intermediate states can be
monitored by background subagents; constraint-violation states require
main agent judgment.
