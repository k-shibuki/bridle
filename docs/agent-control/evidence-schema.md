# Evidence Schema

## Makefile target naming convention

All `make` targets follow a systematic naming convention. The names are
self-documenting: no abbreviations, no jargon that requires project
context to decode.

Scope note: the naming rules below apply to `make` target names only.
They do not constrain CLI flags, environment variable names, or JSON
field names.

### Naming rules

1. **Category prefix**: every target starts with a category that groups
   related targets in `make help` output
2. **No abbreviations**: `knowledge-*` not `kb-*`, `pull-request` not `pr`,
   `continuous-integration` is replaced by descriptive gate names
3. **Verb-object or category-action**: `schema-validate`, `format-verify`,
   `container-start`
4. **`check` reserved for R CMD check**: the word `check` refers exclusively
   to `R CMD check` (a specific R tool). Verification of other conditions
   uses `verify`
5. **Modifier as suffix**: `lint-changed` not `changed-lint`, `test-changed`
   not `changed-test`
6. **Output format as suffix**: `lint-json`, `test-junit`, `doctor-json`
7. **Gate targets use `gate-` prefix**: composite quality targets that
   aggregate multiple checks
8. **Core bare targets are explicit exceptions**: `help`, `clean`,
   `status`, `lint`, `format`, `test`, `check`, `coverage`, and `doctor`
   remain bare because they are established top-level developer entry points

### Category catalog

| Category | Prefix | Purpose |
|----------|--------|---------|
| Container lifecycle | `container-` | Build, start, stop, shell access |
| Package management | `package-` | R dependency management (init, restore, snapshot, install) |
| Quality (individual) | bare or descriptive | Single quality checks (lint, format, test, check) |
| Quality (gates) | `gate-` | Composite gates aggregating multiple checks |
| Evidence | `evidence-` | Structured observation → JSON |
| Knowledge base | `knowledge-` | KB management (manifest, validate, new) |
| Scaffold | `scaffold-` | Code generation from templates |
| Git operations | `git-` | Branch creation, hook installation |
| Environment | `environment-` or reserved doctor targets | Environment health checks and diagnostics |
| Documentation | `document`, `site-build` | Roxygen, pkgdown |
| Meta | bare | `help`, `clean`, `status` |

### Target catalog

This catalog defines the canonical naming set.

| Target | Category |
|--------|----------|
| `help` | meta |
| `clean` | meta |
| `status` | meta |
| `container-build` | container |
| `container-start` | container |
| `container-stop` | container |
| `container-shell` | container |
| `container-rstudio` | container |
| `package-init` | package |
| `package-restore` | package |
| `package-snapshot` | package |
| `package-sync-verify` | package |
| `package-install` | package |
| `lint` | quality |
| `lint-json` | quality |
| `lint-changed` | quality |
| `format` | quality |
| `format-verify` | quality |
| `check` | quality |
| `check-quick` | quality |
| `test` | quality |
| `test-junit` | quality |
| `test-changed` | quality |
| `coverage` | quality |
| `coverage-verify` | quality |
| `schema-validate` | quality |
| `review-sync-verify` | quality |
| `document` | documentation |
| `site-build` | documentation |
| `gate-fast` | gate |
| `gate-quality` | gate |
| `gate-pull-request` | gate |
| `gate-full` | gate |
| `doctor` | environment |
| `doctor-json` | environment |
| `knowledge-manifest` | knowledge |
| `knowledge-validate` | knowledge |
| `knowledge-new` | knowledge |
| `git-install-hooks` | git |
| `git-new-branch` | git |
| `scaffold-class` | scaffold |
| `scaffold-test` | scaffold |
| `evidence-workflow-position` | evidence |
| `evidence-environment` | evidence |
| `evidence-lint` | evidence |
| `evidence-pull-request` | evidence |
| `evidence-review-threads` | evidence |
| `evidence-issue` | evidence |
| `evidence-branch-protection` | evidence |

### Gate hierarchy

Gates are composite targets that run multiple checks. `gate-quality`
through `gate-full` form a strict containment chain. `gate-fast` is a
separate fast-feedback path that overlaps with but is not a subset of
`gate-quality`.

```text
gate-fast         schema-validate + package-sync-verify + knowledge-validate + lint
                  (fast-feedback path — overlaps gate-quality but includes
                   package-sync-verify and knowledge-validate which gate-quality omits)

gate-quality      schema-validate + lint + test + check
    ⊂
gate-pull-request gate-quality + document
    ⊂
gate-full         format-verify + gate-pull-request
```

| Gate | Purpose | When to use |
|------|---------|-------------|
| `gate-fast` | Fast structural feedback | During development, pre-push (partial) |
| `gate-quality` | Full quality verification | CI pipeline equivalent |
| `gate-pull-request` | PR merge readiness | Before PR creation |
| `gate-full` | Complete local verification | Pre-push hook (with format-verify) |

## Evidence target design

Each evidence target is a `make` target backed by a shell script in
`tools/`. It reads external state and produces structured JSON on stdout.
Evidence targets never modify state — they are pure observations.

### Design constraints

- All output is JSON (parseable by `jq`)
- Errors are surfaced through the shared `_errors` envelope documented below
- Targets are idempotent and side-effect free
- Targets that require network access (GitHub API) declare this in their description
- Freshness: evidence is valid for the duration of a single agent turn (no caching across turns)

### `_meta` envelope

Every evidence target wraps its output via `evidence_emit()` in
`tools/evidence-lib.sh`. The function appends a `_meta` object to the
body JSON. Target schemas below document only the body fields; `_meta`
is always present.

```json
{
  "_meta": {
    "target": "string (e.g. evidence-pull-request)",
    "timestamp": "ISO8601 (collection time)",
    "version": "string (evidence-lib version)",
    "duration_ms": "integer (script execution time)"
  },
  "_errors": [
    {
      "source": "string",
      "message": "string",
      "fatal": "boolean"
    }
  ]
}
```

- `_meta` is always present.
- `_errors` is present only when errors were recorded via `evidence_error()`.
- On fatal error, only `_meta` and `_errors` are emitted (no body fields).

### Target 1: `evidence-workflow-position`

**Purpose**: Primary FSM input. Aggregates git, GitHub, and review state
into a single JSON document for state classification.

**Input**: `git`, `gh`, GitHub GraphQL API

**Output schema**:

```json
{
  "git": {
    "branch": "string",
    "on_main": "boolean",
    "uncommitted_files": "integer",
    "stale_branches": ["string"],
    "commits_ahead_of_remote": "integer",
    "stash_count": "integer"
  },
  "issues": {
    "open_count": "integer",
    "open": [
      {
        "number": "integer",
        "title": "string",
        "labels": ["string"],
        "has_test_plan": "boolean",
        "has_acceptance_criteria": "boolean",
        "blocked_by": ["integer"]
      }
    ]
  },
  "pull_requests": {
    "open_count": "integer",
    "open": [
      {
        "number": "integer",
        "title": "string",
        "head_branch": "string",
        "ci_status": "success | failure | pending | no_checks",
        "mergeable": "MERGEABLE | CONFLICTING | UNKNOWN",
        "review_threads_total": "integer",
        "review_threads_unresolved": "integer"
      }
    ],
    "recently_merged": [
      {
        "number": "integer",
        "title": "string",
        "merged_at": "ISO8601"
      }
    ]
  },
  "environment": {
    "container_running": "boolean"
  },
  "routing": {
    "global_state_id": "string"
  },
  "procedure_context": {
    "workflow_phase": "implementing | implementation_done | tests_done | quality_ok | tests_pass | null",
    "issue_number": "integer | null",
    "branch": "string",
    "updated_at": "ISO8601 | null",
    "stale": "boolean"
  }
}
```

**Field semantics**:

- `git.branch`: current HEAD branch name
- `git.on_main`: convenience boolean, true when `branch == "main"`
- `git.uncommitted_files`: count of files from `git status --short` (staged + unstaged + untracked)
- `git.stale_branches`: local branches whose upstream tracking ref is `[gone]`
- `git.commits_ahead_of_remote`: commits not yet pushed (0 if up to date or no upstream)
- `issues.open[].blocked_by`: Issue numbers referenced in "Depends on" or "Blocks" sections
- `pull_requests.open[].ci_status`: aggregated from `statusCheckRollup` — `success` only if ALL checks pass
- `pull_requests.open[].review_threads_*`: from GraphQL `reviewThreads` query
- `environment.container_running`: true when the development container is running. When **false**, `global-workflow.jq` sets `routing.global_state_id` to `EnvironmentIssue` (ST_ENV_ISSUE). Full health diagnosis (renv, R packages, etc.) remains in `evidence-environment` (`errors > 0` also yields `EnvironmentIssue` when merged in `evidence-fsm`).
- `routing.global_state_id`: global FSM id from `docs/agent-control/fsm/global-workflow.jq` with `env_errors` passed as `0` here; container-down is still evaluated from `.environment.container_running`. `evidence-fsm` recomputes the same jq with real `evidence-environment.errors`.
- `procedure_context.workflow_phase`: current local workflow phase from `.cursor/state/workflow-phase.json`. `null` when no active local work or file absent.
- `procedure_context.issue_number`: Issue being worked on (for cross-validation with branch).
- `procedure_context.stale`: `true` if the state file's `branch` does not match current branch, or if `updated_at` is older than 24 hours.

**Nullability**: all fields are required. Empty arrays for absent collections. `blocked_by` may be empty. `procedure_context.workflow_phase`, `procedure_context.issue_number`, and `procedure_context.updated_at` may be null.

**Composability**: this target is self-contained. It does NOT call other evidence targets (routing is post-processed via jq; `evidence-fsm` recomputes global state with environment errors).

**Downstream**: used by FSM state classification (all states), `next` command orientation.

### Target 2: `evidence-environment`

**Purpose**: Detailed environment health check.

**Input**: `tools/doctor.sh --json`

**Output schema**:

```json
{
  "errors": "integer",
  "warnings": "integer",
  "runtime": "podman | docker",
  "checks": [
    {
      "name": "string",
      "status": "ok | error | warning | skip",
      "detail": "string"
    }
  ]
}
```

**Field semantics**:

- `errors`: count of critical issues (environment not usable)
- `warnings`: count of non-critical issues (environment usable but degraded)
- `runtime`: container runtime detected
- `checks[].name`: check identifier (e.g., `"git"`, `"container_running"`, `"r_version"`)
- `checks[].status`: `ok` = passed, `error` = critical failure, `warning` = non-critical, `skip` = not applicable
- `checks[].detail`: human-readable description of result

**Nullability**: all fields required. `detail` may be empty string.

**Composability**: `evidence-workflow-position` exposes `container_running` for lightweight UI; `errors` / `warnings` live here. `ST_ENV_ISSUE` uses `errors > 0` from this target (or the embedded copy in `evidence-fsm`). **Tier B (agents):** run `make evidence-environment` when `evidence-workflow-position.environment.container_running == false` (optional at other times).

**Downstream**: ST_ENV_ISSUE (EnvironmentIssue) detection, `doctor` command.

### Target 3: `evidence-lint`

**Purpose**: Structured lint results for quality verification.

**Input**: `lintr::lint_package()` via container R

**Output schema**:

```json
{
  "file_count": "integer",
  "finding_count": "integer",
  "findings": [
    {
      "file": "string",
      "line": "integer",
      "column": "integer",
      "linter": "string",
      "message": "string",
      "severity": "error | warning | style"
    }
  ]
}
```

**Nullability**: all fields required. `findings` may be empty array.

**Downstream**: verify, ST_TESTS_DONE→ST_QUALITY_OK transition verification.

### Target 4: `evidence-pull-request`

**Purpose**: Detailed state for a specific PR. Includes CI check details,
review freshness, and bot review status.

**Input**: `gh` REST API, GitHub GraphQL API. Requires `PR=<number>` argument.

**Output schema**:

```json
{
  "number": "integer",
  "title": "string",
  "state": "OPEN | MERGED | CLOSED",
  "head_branch": "string",
  "base_branch": "string",
  "routing": {
    "pr_state_id": "string"
  },
  "auto_merge_readiness": {
    "review_consensus_complete": "boolean",
    "ci_all_required_passed": "boolean",
    "blockers": ["string"],
    "safe_to_enable": "boolean"
  },
  "ci": {
    "status": "success | failure | pending | no_checks",
    "checks": [
      {
        "name": "string",
        "status": "pass | fail | pending | skipped",
        "elapsed_seconds": "integer | null"
      }
    ]
  },
  "merge": {
    "mergeable": "MERGEABLE | CONFLICTING | UNKNOWN",
    "merge_state_status": "CLEAN | HAS_HOOKS | BEHIND | DIRTY | BLOCKED | UNKNOWN"
  },
  "reviews": {
    "bot_<id>": {
      "status": "COMPLETED | COMPLETED_CLEAN | COMPLETED_SILENT | RATE_LIMITED | TIMED_OUT | NOT_TRIGGERED | PENDING | REVIEW_INVALIDATED",
      "review_submitted_at": "ISO8601 | null",
      "findings_count": "integer",
      "review_count": "integer",
      "max_reviews": "integer | null"
    },
    "threads_total": "integer",
    "threads_unresolved": "integer",
    "review_threads_truncated": "boolean",
    "disposition": "approved | changes_requested | pending",
    "last_review_at": "ISO8601 | null",
    "last_push_at": "ISO8601",
    "diagnostics": {
      "bot_review_completed": "boolean",
      "bot_review_failed": "boolean",
      "bot_review_terminal": "boolean",
      "bot_review_pending": "boolean",
      "required_bot_findings_total": "integer",
      "required_bot_findings_outstanding": "boolean",
      "non_thread_bot_findings_outstanding": "boolean",
      "rereview_response_pending": "boolean"
    },
    "re_review_signal": {
      "latest_cr_trigger_created_at": "ISO8601 | null",
      "latest_cr_review_submitted_at_after_trigger": "ISO8601 | null",
      "cr_response_pending_after_latest_trigger": "boolean",
      "trigger_comment_log": [{ "created_at": "ISO8601", "id": "integer" }]
    }
  },
  "traceability": {
    "closes_issues": ["integer"],
    "has_exception_label": "boolean",
    "exception_type": "hotfix | no-issue | null"
  }
}
```

**Field semantics**:

- `state`: PR lifecycle state from GitHub (`OPEN`, `MERGED`, `CLOSED`)
- `ci.checks[].elapsed_seconds`: null if check has not completed
- `reviews.last_push_at`: timestamp of most recent push to PR branch (for review freshness)
- `reviews.last_review_at`: timestamp of most recent review submission (null if none)
- `reviews.disposition`: merged disposition from review timeline used by FSM transitions
- `reviews.bot_<id>`: dynamically generated from `docs/agent-control/review-bots.json` config. Each configured bot produces a `bot_<id>` key.
- `reviews.bot_<id>.findings_count`: total findings from that reviewer, including both inline review comments and body-embedded "outside diff range" findings (0 for clean/silent)
- `reviews.bot_<id>.review_count`: total number of review submissions for this PR
- `reviews.bot_<id>.max_reviews`: copied from `docs/agent-control/review-bots.json` for that bot id (**SSOT** for the per-PR review request cap; `null` if unlimited)
- Bot registry (`docs/agent-control/review-bots.json`) may set `commit_status_name` (substring matched case-insensitively against `statusCheckRollup[].name`), `invalidate_review_pattern` (regex against PR **issue** comments since `last_push_at` — match yields `REVIEW_INVALIDATED`), `trigger` (`agent` \| `user_only`), and `fallback_priority` (nullable number, lower = earlier in human-invoked fallback). When `commit_status_name` matches a rollup entry, `evidence-pull-request` uses that check as the primary signal for `bot_<id>.status` and excludes it from `ci` aggregation.
- `reviews.diagnostics.*`: FSM-aligned aggregates derived from configured bots (`review-bots.json`, including `required`) and thread/disposition state — see `docs/agent-control/fsm/pull-request-readiness.jq` and `docs/agent-control/state-model.md` § Review signals
- `reviews.diagnostics.rereview_response_pending`: same boolean as `reviews.re_review_signal.cr_response_pending_after_latest_trigger`, passed into `pull-request-readiness.jq` as `rereview_response_pending`
- `reviews.diagnostics.required_bot_findings_outstanding`: `true` when the sum of `findings_count` over **required** bots (`review-bots.json`) is greater than zero (includes body-only / outside-diff-range findings that do not create `reviewThreads`)
- `reviews.diagnostics.non_thread_bot_findings_outstanding`: `true` when `required_bot_findings_outstanding` and `threads_unresolved == 0` (actionable bot output with no open GitHub review threads — still blocks merge consensus for pending disposition)
- `reviews.review_threads_truncated`: `true` when GraphQL `reviewThreads(first: 100)` reports `pageInfo.hasNextPage` — unresolved counts may be incomplete; `pull-request-readiness.jq` adds blocker `review_threads_truncated` and routes `UnresolvedThreads`
- `reviews.re_review_signal`: detects PR **issue** comments that request CodeRabbit (`@coderabbitai` and `review`, case-insensitive) and compares the latest such `created_at` to (a) `pulls/.../reviews` from `coderabbitai[bot]` with `submitted_at` strictly after that trigger, and (b) `bot_coderabbit.review_submitted_at` when it is derived from commit-status completion (`commit_status_name` in `review-bots.json`) and is also strictly after the trigger. `cr_response_pending_after_latest_trigger` is `true` when a trigger exists and neither signal shows a completion after the trigger. **Always `false`** when `bot_coderabbit.status == REVIEW_INVALIDATED` (avoid deadlock; re-trigger procedurally). Does not add extra pending solely for `RATE_LIMITED` / `PENDING` (those use existing bot blockers).
- `reviews.re_review_signal.trigger_comment_log`: up to five most recent qualifying trigger comments (same filter as above), newest first, each `{created_at, id}` — debugging / disambiguation when `latest_cr_trigger_created_at` alone is ambiguous
- `auto_merge_readiness`: merge/consensus gate (`safe_to_enable` requires empty `blockers`); same jq SSOT as `routing.pr_state_id`
- `traceability.closes_issues`: Issue numbers from `Closes #N` / `Fixes #N` in PR body

**Nullability**: all top-level fields required. Nullable fields marked with `| null`.

**Downstream**: ST_CI_PENDING–ST_REBASE states, `pr-review`, `pr-merge`, `review-fix`.

### Target 4b: `evidence-fsm`

**Purpose**: Single aggregate for merge/consensus gating and FSM orientation. Runs `evidence-environment` → strips `routing` from `evidence-workflow-position` and recomputes `routing.global_state_id` with real `errors` → (on `main` with open issues) `evidence-issue` → (if an open PR exists for the current branch) `evidence-pull-request`; then merges via `docs/agent-control/fsm/effective-state.jq`.

**Input**: `tools/evidence-fsm.sh` (no arguments).

**Output**: `workflow_position`, `environment`, `issues_summary` (or `null`), `pull_request` (or `null`), `routing` (`effective_state_id`, `global_state_id`, `pr_state_id`, `recommended_next_issue`).

**Downstream**: `HS-MERGE-CONSENSUS`, `next` orientation when a unified view is required.

### Target 5: `evidence-review-threads`

**Purpose**: Per-thread review details for `review-fix` (disposition replies, thread resolution) and `pr-review` (finding classification).

**Input**: GitHub GraphQL API + REST API + `gh pr diff`. Requires `PR=<number>` argument.

**Output schema**:

```json
{
  "total": "integer",
  "unresolved": "integer",
  "threads": [
    {
      "graphql_id": "string (GraphQL node ID for resolveReviewThread)",
      "is_resolved": "boolean",
      "is_outdated": "boolean",
      "path": "string | null",
      "line": "integer | null",
      "author": "string",
      "body": "string (first comment body)",
      "database_id": "integer (REST API comment ID for replies)",
      "replies": [
        {
          "database_id": "integer",
          "author": "string",
          "body": "string",
          "created_at": "ISO8601"
        }
      ]
    }
  ],
  "body_findings": [
    {
      "review_id": "integer",
      "author": "string",
      "path": "string",
      "line_range": "string (e.g. '121-121')",
      "body": "string (finding title)",
      "submitted_at": "ISO8601"
    }
  ],
  "body_findings_count": "integer",
  "files_changed": ["string"],
  "truncated": "boolean"
}
```

**Field semantics**:

- `truncated`: true if GraphQL pagination limits were hit (>100 threads or >20 comments per thread). When true, `_errors` contains details about which connection was truncated.
- `graphql_id`: required for `resolveReviewThread` GraphQL mutation
- `database_id`: required for `POST /pulls/{N}/comments/{id}/replies` REST API
- `body`: first comment in thread (the reviewer's finding)
- `replies`: subsequent comments (disposition replies, bot confirmations)
- `body_findings`: findings embedded in review body as "outside diff range comments". These are not GitHub review threads and do not affect `required_conversation_resolution`. Extracted from `<summary>filepath (N)</summary>` sections in review bodies.
- `body_findings_count`: total number of body-embedded findings across all reviews (0 if none)
- `files_changed`: paths from `gh pr diff --name-only`

**Nullability**: all top-level fields required. `path` and `line` nullable (for PR-level comments outside diff). `body_findings` may be empty array.

**Downstream**: `review-fix` Steps 1 (classify findings) and 3 (post disposition + check consensus), `pr-review` Step 2 (thread baseline).

### Target 6: `evidence-issue`

**Purpose**: Issue metadata for prioritization and dependency analysis.

**Input**: `gh` REST API. Optional `ISSUE=<number>`; optional `SCOPE=control-system` or `ISSUE_MIN=<n>` to filter (control-system: label `agent-control` or number >= ISSUE_MIN; default ISSUE_MIN 252). Without ISSUE, returns open Issues (subject to scope filter).

**Output schema**:

```json
{
  "issues": [
    {
      "number": "integer",
      "title": "string",
      "labels": ["string"],
      "body": "string (full Issue body text)",
      "has_test_plan": "boolean",
      "has_acceptance_criteria": "boolean",
      "blocked_by": ["integer"],
      "blocks": ["integer"],
      "is_parent": "boolean",
      "child_issues": ["integer"],
      "children_closed": "boolean",
      "parent_closeable": "boolean",
      "assignee": "string | null",
      "created_at": "ISO8601"
    }
  ],
  "dependency_graph": {
    "roots": ["integer"],
    "leaves": ["integer"],
    "depth": "integer"
  }
}
```

**Field semantics**:

- `body`: full Issue body text including DoD, test plan, and acceptance criteria sections
- `is_parent`: true if Issue has sub-issues (detected via "## Sub-issues" section)
- `child_issues`: list of Issue numbers from the `## Sub-issues` section (parent only). Parsed from list lines matching `^\s*[-*]\s+(?:\[[ xX]\]\s*)?#(\d+)` within that section; section runs until next `##` or end of body. Allowed forms: `- [ ] #N`, `- [x] #N`, `- #N`, `* [ ] #N` (SSOT: workflow-policy).
- `children_closed`: true iff every `child_issues` Issue has state closed (via `gh issue view N --json state`; checkbox in body is not authoritative).
- `parent_closeable`: true iff `is_parent` and `children_closed`; when false and PR would close the parent, pr-policy fails.
- `blocked_by` / `blocks`: extracted from Issue body dependency references
- `dependency_graph.roots`: Issues with no blockers (can start immediately)
- `dependency_graph.leaves`: Issues that block nothing
- `dependency_graph.depth`: maximum dependency chain length

**Nullability**: all fields required. `assignee` nullable. Arrays may be empty.

**Downstream**: ST_PREFLIGHT (PreFlightReview), ST_READY (ReadyToStart) Issue selection, `implement` auto-select.

### Target 7: `evidence-branch-protection`

**Purpose**: Observe GitHub branch protection for a branch (default `main`) without raw `gh api` in procedures.

**Input**: `gh` REST API `GET /repos/{owner}/{repo}/branches/{branch}/protection`. `BRANCH` env optional (default `main`). Repo resolved from `git remote origin`.

**Output schema**:

```json
{
  "repo_owner": "string",
  "repo_name": "string",
  "branch": "string",
  "protection_present": "boolean",
  "required_status_checks_strict": "boolean | null",
  "required_status_contexts": ["string"]
}
```

**Field semantics**:

- `protection_present`: false when GitHub returns 404 (no rules on branch) or on fatal resolution errors
- `required_status_checks_strict`: from GitHub `required_status_checks.strict` when protection exists; null when absent
- `required_status_contexts`: GitHub `required_status_checks.contexts` when protection exists; empty when absent

**Nullability**: all fields required in successful output; `required_status_checks_strict` may be null.

**Downstream**: `controls-review.md` guard audit (branch protection row).
