# FSM / State Model

## State catalog

Each state represents a distinct workflow position with a defined set
of available transitions.

| ID | State | Description | Entry condition |
|----|-------|-------------|-----------------|
| S01 | `NoWorkPlanned` | No open Issues exist | `open_issues == 0` |
| S02 | `PreFlightReview` | Issues exist but have not been reviewed for quality | `open_issues > 0 AND on_main AND no_uncommitted AND issues_not_reviewed` |
| S03 | `ReadyToStart` | Actionable Issues exist, ready to implement | `open_issues > 0 AND on_main AND no_uncommitted` |
| S04 | `Implementing` | On feature branch, implementation in progress | `on_feature_branch AND uncommitted_changes AND no_tests_for_changes` |
| S05 | `ImplementationDone` | Code written, tests not yet created | `on_feature_branch AND implementation_files_changed AND no_test_files_changed` |
| S06 | `TestsDone` | Tests created, quality not yet checked | `on_feature_branch AND test_files_exist AND quality_not_verified` |
| S07 | `QualityOK` | Quality gates passed, tests not run as full suite | `on_feature_branch AND quality_passed AND full_suite_not_run` |
| S08 | `TestsPass` | Full test suite passed, docs not reviewed | `on_feature_branch AND full_suite_passed AND docs_not_reviewed` |
| S09 | `DocsOK` | Documentation reviewed/updated, uncommitted changes remain | `on_feature_branch AND docs_reviewed AND uncommitted_changes` |
| S10 | `Committed` | All changes committed, no PR exists | `on_feature_branch AND no_uncommitted AND no_open_pr_for_branch` |
| S11 | `CIPending` | PR exists, CI still running | `open_pr AND ci_status == "pending"` |
| S12 | `CIFailed` | PR exists, CI failed | `open_pr AND ci_status == "failure"` |
| S13 | `BotReviewPending` | CI green, bot review not yet complete | `open_pr AND ci_status == "success" AND bot_review_status == "pending"` |
| S14 | `UnresolvedThreads` | Review threads exist that lack consensus | `open_pr AND review_threads_unresolved > 0` |
| S15 | `ReadyForReview` | CI green, bot review complete, agent review needed | `open_pr AND ci_status == "success" AND bot_review_terminal AND agent_review_not_done` |
| S16 | `ChangesRequired` | Review complete, changes requested | `open_pr AND review_disposition == "changes_requested"` |
| S17 | `ReviewDone` | Review complete, mergeable | `open_pr AND review_disposition == "approved" AND mergeable` |
| S18 | `DependentChainRebase` | Merge conflict from squash-merged parent PR | `open_pr AND mergeable_status == "CONFLICTING" AND parent_pr_recently_merged` |
| S19 | `StaleBranches` | Local branches track deleted remotes | `stale_branches_count > 0` |
| S20 | `CycleComplete` | PR merged, back on main | `on_main AND pr_just_merged` |
| S21 | `EnvironmentIssue` | Development environment unhealthy | `doctor_healthy == false` |
| S22 | `ExceptionFlow` | Hotfix or no-issue exception needed | `on_main AND exception_needed` |

**State classification**:

- **Progress states** (S03–S10, S20): normal forward movement through the workflow
- **Waiting states** (S11, S13): blocked on external process
- **Intervention states** (S12, S14, S16, S18): require agent action to resolve
- **Maintenance states** (S01, S02, S19, S21): housekeeping or setup
- **Terminal states** (S17): ready for final action (merge)

## Signal catalog

Signals are observable facts derived from Evidence targets. Each signal
has a defined type, source, and interpretation.

### Git signals

| Signal | Type | Source | Interpretation |
|--------|------|--------|---------------|
| `branch_name` | string | `git branch --show-current` | Current branch name |
| `on_main` | boolean | derived | `branch_name == "main"` |
| `on_feature_branch` | boolean | derived | `branch_name != "main"` |
| `uncommitted_files` | integer | `git status --short` | Count of modified/untracked files |
| `no_uncommitted` | boolean | derived | `uncommitted_files == 0` |
| `stale_branches` | string[] | `git branch` + upstream tracking | Branches whose remote tracking ref is gone |
| `stale_branches_count` | integer | derived | Length of `stale_branches` |
| `commits_ahead` | integer | `git rev-list` | Commits ahead of remote |

### GitHub signals

| Signal | Type | Source | Interpretation |
|--------|------|--------|---------------|
| `open_issues` | object[] | `gh issue list` | Open Issues with metadata |
| `open_issues_count` | integer | derived | Count of open Issues |
| `open_prs` | object[] | `gh pr list` | Open PRs with metadata |
| `open_pr_for_branch` | object \| null | derived | PR matching current branch |
| `recently_merged_prs` | object[] | `gh pr list --state merged` | Recently merged PRs (last 5) |

### CI signals

| Signal | Type | Source | Interpretation |
|--------|------|--------|---------------|
| `ci_status` | enum | `gh pr checks` | `"success"` \| `"failure"` \| `"pending"` \| `"no_checks"` |
| `ci_failed_jobs` | string[] | `gh pr checks` | Names of failed CI jobs |
| `mergeable_status` | enum | `gh pr view --json mergeable` | `"MERGEABLE"` \| `"CONFLICTING"` \| `"UNKNOWN"` |
| `merge_state_status` | enum | `gh pr view --json mergeStateStatus` | `"CLEAN"` \| `"HAS_HOOKS"` \| `"BEHIND"` \| `"DIRTY"` \| `"BLOCKED"` \| `"UNKNOWN"` |

### Review signals

| Signal | Type | Source | Interpretation |
|--------|------|--------|---------------|
| `review_threads_total` | integer | GraphQL | Total review thread count |
| `review_threads_unresolved` | integer | GraphQL | Unresolved thread count |
| `bot_coderabbit_status` | enum | REST API detection | `"COMPLETED"` \| `"COMPLETED_CLEAN"` \| `"COMPLETED_SILENT"` \| `"RATE_LIMITED"` \| `"TIMED_OUT"` \| `"NOT_TRIGGERED"` \| `"PENDING"` |
| `bot_codex_status` | enum | REST API detection | Same as CodeRabbit + `"COMPLETED_CLEAN"` (thumbs-up) |
| `review_disposition` | enum | `gh api pulls/<N>/reviews` | `"approved"` \| `"changes_requested"` \| `"pending"` |

### Environment signals

| Signal | Type | Source | Interpretation |
|--------|------|--------|---------------|
| `doctor_healthy` | boolean | `make doctor-json` | `errors == 0` |
| `doctor_errors` | integer | `make doctor-json` | Critical issue count |
| `doctor_warnings` | integer | `make doctor-json` | Warning count |
| `container_running` | boolean | `make doctor-json` | Dev container status |

## Transition table

Transitions define which state changes are valid and what triggers them.

| From | Signal condition | To | Action |
|------|------------------|----|--------|
| S01 | — | S01 | `issue-create` |
| S02 | issues reviewed | S03 | `issue-review` → complete |
| S03 | issue selected | S04 | `implement` (branch created) |
| S04 | implementation complete | S05 | Agent signals completion |
| S05 | — | S06 | `test-create` |
| S06 | — | S07 | `quality-check` |
| S07 | — | S08 | `test-regression` |
| S08 | — | S09 | `docs-discover` (Mode 2) |
| S09 | — | S10 | `commit` |
| S10 | — | S11 | `pr-create` (triggers CI + bot review) |
| S11 | `ci_status == "success"` | S13 | CI completes green |
| S11 | `ci_status == "failure"` | S12 | CI fails |
| S12 | fix pushed | S11 | Re-enter CI pending |
| S13 | `bot_coderabbit_status` terminal | S15 | Bot review complete |
| S13 | `bot_coderabbit_status == "RATE_LIMITED"` | S13 | Recovery: sleep + re-trigger |
| S14 | all threads resolved | S15 or S17 | `review-fix` |
| S15 | review complete, approved | S17 | `pr-review` → approved |
| S15 | review complete, changes needed | S16 | `pr-review` → changes requested |
| S16 | fix pushed | S11 | Re-enter CI pending |
| S17 | — | S20 | `pr-merge` |
| S18 | rebase complete, pushed | S11 | Re-enter CI pending |
| S19 | branches deleted | S03 or S01 | Cleanup, re-assess |
| S20 | open Issues remain | S03 | Start next Issue |
| S20 | no open Issues | S01 | All work complete |
| S21 | environment fixed | S03 or S01 | `doctor` → re-assess |
| S22 | — | S10 | `implement` → `pr-create` (exception path) |

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
