# FSM / State Model

## State catalog

Each state represents a distinct workflow position with a defined set
of available transitions.

| ID | State | Description | Entry condition |
|----|-------|-------------|-----------------|
| S01 | `NoWorkPlanned` | No open Issues exist | `open_issues_count == 0` |
| S02 | `PreFlightReview` | Issues exist but have not been reviewed for quality | `open_issues_count > 0 AND on_main AND no_uncommitted AND issues_require_preflight_review` |
| S03 | `ReadyToStart` | Actionable Issues exist, ready to implement | `open_issues_count > 0 AND on_main AND no_uncommitted AND issues_require_preflight_review == false` |
| S04 | `Implementing` | On feature branch, implementation in progress | `on_feature_branch AND workflow_phase == "implementing"` |
| S05 | `ImplementationDone` | Code written, tests not yet created | `on_feature_branch AND workflow_phase == "implementation_done"` |
| S06 | `TestsDone` | Tests created, quality not yet checked | `on_feature_branch AND workflow_phase == "tests_done"` |
| S07 | `QualityOK` | Quality gates passed, tests not run as full suite | `on_feature_branch AND workflow_phase == "quality_ok"` |
| S08 | `TestsPass` | Full test suite passed, docs not reviewed | `on_feature_branch AND workflow_phase == "tests_pass"` |
| S09 | `DocsOK` | Documentation reviewed/updated, uncommitted changes remain | `on_feature_branch AND workflow_phase == "docs_ok"` |
| S10 | `Committed` | All changes committed, no PR exists | `on_feature_branch AND no_uncommitted AND pr_exists_for_branch == false` |
| S11 | `CIPending` | PR exists, CI still running | `pr_exists_for_branch AND ci_status == "pending"` |
| S12 | `CIFailed` | PR exists, CI failed | `pr_exists_for_branch AND ci_status == "failure"` |
| S13 | `BotReviewPending` | CI green, bot review not yet complete | `pr_exists_for_branch AND ci_status == "success" AND bot_review_pending` |
| S14 | `UnresolvedThreads` | Review threads exist that lack consensus | `pr_exists_for_branch AND review_threads_unresolved > 0` |
| S15 | `ReadyForReview` | CI green, bot review complete, agent review needed | `pr_exists_for_branch AND ci_status == "success" AND bot_review_terminal AND review_threads_unresolved == 0 AND review_disposition == "pending"` |
| S16 | `ChangesRequired` | Review complete, changes requested | `pr_exists_for_branch AND review_disposition == "changes_requested"` |
| S17 | `ReviewDone` | Review complete, mergeable | `pr_exists_for_branch AND review_disposition == "approved" AND mergeable_status == "MERGEABLE"` |
| S18 | `DependentChainRebase` | Merge conflict from squash-merged parent PR | `pr_exists_for_branch AND mergeable_status == "CONFLICTING" AND parent_pr_recently_merged` |
| S19 | `StaleBranches` | Local branches track deleted remotes | `stale_branches_count > 0` |
| S20 | `CycleComplete` | PR merged, back on main | `on_main AND pr_just_merged` |
| S21 | `EnvironmentIssue` | Development environment unhealthy | `doctor_healthy == false` |
| S22 | `ExceptionFlow` | Hotfix or no-issue exception needed | `on_main AND exception_issue_exists` |

**State classification**:

- **Progress states** (S03–S10, S20): normal forward movement through the workflow
- **Waiting states** (S11, S13): blocked on external process
- **Intervention states** (S12, S14, S16, S18): require agent action to resolve
- **Maintenance states** (S01, S02, S19, S21): housekeeping or setup
- **Terminal states** (S17): ready for final action (merge)

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
| `bot_coderabbit_status` | enum | `evidence-pull-request.reviews.bot_coderabbit.status` | `"COMPLETED"` \| `"COMPLETED_CLEAN"` \| `"COMPLETED_SILENT"` \| `"RATE_LIMITED"` \| `"TIMED_OUT"` \| `"NOT_TRIGGERED"` \| `"PENDING"` |
| `bot_codex_status` | enum | `evidence-pull-request.reviews.bot_codex.status` | `"COMPLETED"` \| `"COMPLETED_CLEAN"` \| `"RATE_LIMITED"` \| `"TIMED_OUT"` \| `"NOT_TRIGGERED"` \| `"PENDING"` |
| `bot_review_pending` | boolean | derived | Either bot status is `PENDING` or `NOT_TRIGGERED` |
| `bot_review_terminal` | boolean | derived | Both bot statuses are terminal (`COMPLETED*`, `TIMED_OUT`, `RATE_LIMITED`) |
| `review_disposition` | enum | `evidence-pull-request.reviews.disposition` | `"approved"` \| `"changes_requested"` \| `"pending"` |

### Environment signals

| Signal | Type | Source | Interpretation |
|--------|------|--------|---------------|
| `doctor_healthy` | boolean | `evidence-workflow-position.environment.doctor_healthy` (preferred), fallback `evidence-environment.errors` | `errors == 0` |
| `errors` | integer | `evidence-environment.errors` | Critical issue count |
| `warnings` | integer | `evidence-environment.warnings` | Warning count |
| `container_running` | boolean | `evidence-workflow-position.environment.container_running` | Dev container status |

### Procedure-context signals

| Signal | Type | Source | Interpretation |
|--------|------|--------|---------------|
| `workflow_phase` | enum | Procedure context | `"implementing"` \| `"implementation_done"` \| `"tests_done"` \| `"quality_ok"` \| `"tests_pass"` \| `"docs_ok"` |
| `selected_issue_number` | integer \| null | Procedure context | Issue selected for current implementation cycle |

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
| `open_issues` | `evidence-workflow-position` | `issues.open` |
| `open_issues_count` | `evidence-workflow-position` | `issues.open_count` |
| `open_prs` | `evidence-workflow-position` | `pull_requests.open` |
| `recently_merged_prs` | `evidence-workflow-position` | `pull_requests.recently_merged` |
| `ci_status` | `evidence-pull-request` | `ci.status` |
| `mergeable_status` | `evidence-pull-request` | `merge.mergeable` |
| `merge_state_status` | `evidence-pull-request` | `merge.merge_state_status` |
| `review_threads_total` | `evidence-pull-request` | `reviews.threads_total` |
| `review_threads_unresolved` | `evidence-pull-request` | `reviews.threads_unresolved` |
| `bot_coderabbit_status` | `evidence-pull-request` | `reviews.bot_coderabbit.status` |
| `bot_codex_status` | `evidence-pull-request` | `reviews.bot_codex.status` |
| `review_disposition` | `evidence-pull-request` | `reviews.disposition` |
| `doctor_healthy` | `evidence-workflow-position` | `environment.doctor_healthy` |
| `container_running` | `evidence-workflow-position` | `environment.container_running` |
| `errors` | `evidence-environment` | `errors` |
| `warnings` | `evidence-environment` | `warnings` |
| `issues_require_preflight_review` | `evidence-issue` | `issues[].has_test_plan`, `issues[].has_acceptance_criteria` |
| `exception_issue_exists` | `evidence-issue` | `issues[].labels[]` |
| `workflow_phase` | N/A (procedure context) | `procedure_context.workflow_phase` |
| `selected_issue_number` | N/A (procedure context) | `procedure_context.selected_issue_number` |

## Transition table

Transitions define which state changes are valid. `Signal condition`
contains machine-evaluable expressions. `Trigger event` is optional and
captures explicit user/agent actions.

| From | Signal condition | Trigger event | To | Action |
|------|------------------|---------------|----|--------|
| S01 | `open_issues_count == 0` | none | S01 | `issue-create` |
| S02 | `issues_require_preflight_review == false` | `issue-review` completed | S03 | Continue workflow |
| S03 | `selected_issue_number != null` | Issue selected | S04 | `implement` (branch created) |
| S04 | `workflow_phase == "implementation_done"` | Implement step complete | S05 | Continue workflow |
| S05 | `workflow_phase == "tests_done"` | `test-create` completed | S06 | Continue workflow |
| S06 | `workflow_phase == "quality_ok"` | `quality-check` completed | S07 | Continue workflow |
| S07 | `workflow_phase == "tests_pass"` | `test-regression` completed | S08 | Continue workflow |
| S08 | `workflow_phase == "docs_ok"` | `docs-discover` (Mode 2) completed | S09 | Continue workflow |
| S09 | `no_uncommitted AND pr_exists_for_branch == false` | `commit` completed | S10 | Continue workflow |
| S10 | `pr_exists_for_branch` | `pr-create` completed | S11 | CI + bot review start |
| S11 | `ci_status == "success"` | none | S13 | Wait for bot terminal state |
| S11 | `ci_status == "failure"` | none | S12 | Diagnose and fix |
| S12 | `ci_status == "pending"` | fix pushed | S11 | Re-enter CI pending |
| S13 | `bot_review_terminal` | none | S15 | Ready for human/agent review |
| S13 | `bot_coderabbit_status == "RATE_LIMITED" OR bot_codex_status == "RATE_LIMITED"` | none | S13 | Recovery: sleep + re-trigger |
| S14 | `review_threads_unresolved == 0 AND review_disposition == "pending"` | `review-fix` completed | S15 | Ready for review |
| S14 | `review_threads_unresolved == 0 AND review_disposition == "approved"` | `review-fix` completed | S17 | Mergeable review state |
| S15 | `review_disposition == "approved"` | `pr-review` completed | S17 | Ready to merge |
| S15 | `review_disposition == "changes_requested"` | `pr-review` completed | S16 | Fix required |
| S16 | `ci_status == "pending"` | fix pushed | S11 | Re-enter CI pending |
| S17 | `mergeable_status == "MERGEABLE"` | `pr-merge` completed | S20 | Cycle complete |
| S18 | `ci_status == "pending"` | rebase complete and pushed | S11 | Re-enter CI pending |
| S19 | `stale_branches_count == 0 AND open_issues_count > 0` | cleanup completed | S03 | Resume implementation |
| S19 | `stale_branches_count == 0 AND open_issues_count == 0` | cleanup completed | S01 | No work planned |
| S20 | `open_issues_count > 0` | none | S03 | Start next Issue |
| S20 | `open_issues_count == 0` | none | S01 | All work complete |
| S21 | `doctor_healthy` | environment fixed | S03 or S01 | `doctor` then reassess |
| S22 | `exception_issue_exists` | exception flow approved | S10 | `implement` → `pr-create` |

## Guard conditions

Guards are transitions that are **prohibited** regardless of other
conditions. They correspond to Hard Stops in `agent-safety.mdc`.

| Guard ID | Prohibited transition | Enforcement |
|----------|-----------------------|-------------|
| `HS-CI-MERGE` | S17 → S20 when `ci_status != "success"` | GitHub Branch Protection |
| `HS-CI-MERGE(a)` | Any merge using `--admin` flag | Agent self-policing |
| `HS-CI-MERGE(b)` | Amend + force-push in PR flow | Agent self-policing |
| `HS-LOCAL-VERIFY` | S10 → S11 without pre-push verification | `pre-push` Git hook |
| `HS-NO-SKIP` | Any state skip (e.g., S05 → S10) | Partial: `pr-policy.yaml` DoD check |
| `HS-PR-TEMPLATE` | S10 → S11 without full PR template | `pr-policy.yaml` CI check |
| `HS-NO-DISMISS` | Ignoring quality gate errors | Agent self-policing |
| `HS-NOLINT` | Adding `# nolint` without knowledge consultation | `pre-commit` hook (format) + agent self-policing (consultation) |
| `HS-PR-BASE` | S10 → S11 with `--base feat/<branch>` | `pr-policy.yaml` CI check |
| `HS-REVIEW-RESOLVE` | S14 → S17 without per-thread consensus | GitHub Branch Protection `required_conversation_resolution` |

## Error states and recovery

| Error state | Detection | Recovery path |
|-------------|-----------|---------------|
| CI failure (S12) | `ci_status == "failure"` | Diagnose (`ci--failure-triage.md`), fix, re-push → S11 |
| Merge conflict (S18) | `mergeable_status == "CONFLICTING"` + parent PR merged | `git rebase --onto` (`git--squash-merge-dependent-branch.md`), force-push → S11 |
| Bot rate limited | `bot_*_status == "RATE_LIMITED"` | Parse wait time, sleep, re-trigger → S13 |
| Bot timed out | `bot_*_status == "TIMED_OUT"` | Report, proceed with available evidence → S15 |
| Environment broken (S21) | `doctor_healthy == false` | `make container-build` / `make container-start` / `make package-restore` |
| Format-lint loop | styler and lintr disagree | `lint--styler-lintr-conflict.md` |
| Pre-push rejection | Hook fails | Fix locally, re-attempt push |
| `check-policy` failure | PR body missing sections | Edit PR body directly (no commit needed) |

## Priority rules

When multiple states could apply simultaneously, use this precedence
(highest first):

1. **S21 (EnvironmentIssue)** — nothing works without a healthy environment
2. **S12 (CIFailed)** — failing CI blocks all PR progress
3. **S18 (DependentChainRebase)** — merge conflicts block merge
4. **S14 (UnresolvedThreads)** — unresolved threads block merge
5. **S16 (ChangesRequired)** — review findings need addressing
6. **S19 (StaleBranches)** — cleanup, can be done during housekeeping
7. **All other states** — follow normal transition order

## Intermediate states vs constraint-violation states

- **Intermediate states** (S04, S11, S13): the workflow is progressing
  normally but an external process has not completed. No agent action
  needed beyond monitoring.
- **Constraint-violation states** (S12, S14, S16, S18, S21): a
  constraint is violated and the agent must take corrective action
  before the workflow can proceed.

The distinction matters for delegation: intermediate states can be
monitored by background subagents; constraint-violation states require
main agent judgment.
