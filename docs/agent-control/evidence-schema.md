# Evidence Schema

## Makefile target naming convention

All `make` targets follow a systematic naming convention. The names are
self-documenting: no abbreviations, no jargon that requires project
context to decode.

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
| Documentation | `document`, `site-build` | Roxygen, pkgdown |
| Meta | bare | `help`, `clean`, `status` |

### Target catalog

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
| `evidence-issue` | evidence |

### Gate hierarchy

Gates are composite targets that run multiple checks. They form a
strict containment hierarchy:

```
gate-fast         schema-validate + package-sync-verify + knowledge-validate + lint
    ⊂
gate-quality      schema-validate + lint + test + check
    ⊂
gate-pull-request gate-quality + document
    ⊂
gate-full         format-verify + gate-quality + document
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
- Error output uses a unified schema: `{"error": "<message>", "source": "<target>"}`
- Targets are idempotent and side-effect free
- Targets that require network access (GitHub API) declare this in their description
- Freshness: evidence is valid for the duration of a single agent turn (no caching across turns)

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
    "commits_ahead_of_remote": "integer"
  },
  "issues": {
    "open_count": "integer",
    "open": [
      {
        "number": "integer",
        "title": "string",
        "labels": ["string"],
        "has_test_plan": "boolean",
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
    "doctor_healthy": "boolean",
    "container_running": "boolean"
  },
  "timestamp": "ISO8601"
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
- `environment.doctor_healthy`: `errors == 0` from doctor output
- `timestamp`: when this evidence was collected

**Nullability**: all fields are required. Empty arrays for absent collections. `blocked_by` may be empty.

**Composability**: this target is self-contained. It does NOT call other evidence targets.

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
  ],
  "timestamp": "ISO8601"
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

**Composability**: `evidence-workflow-position` extracts `doctor_healthy` and `container_running` from the same underlying doctor check, but does NOT depend on this target.

**Downstream**: S21 (EnvironmentIssue) detection, `doctor` command.

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
  ],
  "timestamp": "ISO8601"
}
```

**Nullability**: all fields required. `findings` may be empty array.

**Downstream**: quality-check, S06→S07 transition verification.

### Target 4: `evidence-pull-request`

**Purpose**: Detailed state for a specific PR. Includes CI check details,
review freshness, and bot review status.

**Input**: `gh` REST API, GitHub GraphQL API. Requires `PR=<number>` argument.

**Output schema**:

```json
{
  "number": "integer",
  "title": "string",
  "head_branch": "string",
  "base_branch": "string",
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
    "bot_coderabbit": {
      "status": "COMPLETED | COMPLETED_CLEAN | COMPLETED_SILENT | RATE_LIMITED | TIMED_OUT | NOT_TRIGGERED | PENDING",
      "review_submitted_at": "ISO8601 | null",
      "findings_count": "integer"
    },
    "bot_codex": {
      "status": "COMPLETED | COMPLETED_CLEAN | RATE_LIMITED | TIMED_OUT | NOT_TRIGGERED | PENDING",
      "review_submitted_at": "ISO8601 | null",
      "findings_count": "integer"
    },
    "threads_total": "integer",
    "threads_unresolved": "integer",
    "last_review_at": "ISO8601 | null",
    "last_push_at": "ISO8601"
  },
  "traceability": {
    "closes_issues": ["integer"],
    "has_exception_label": "boolean",
    "exception_type": "hotfix | no-issue | null"
  },
  "timestamp": "ISO8601"
}
```

**Field semantics**:

- `ci.checks[].elapsed_seconds`: null if check has not completed
- `reviews.last_push_at`: timestamp of most recent push to PR branch (for review freshness)
- `reviews.last_review_at`: timestamp of most recent review submission (null if none)
- `reviews.bot_*.findings_count`: number of findings from that reviewer (0 for clean/silent)
- `traceability.closes_issues`: Issue numbers from `Closes #N` / `Fixes #N` in PR body

**Nullability**: all top-level fields required. Nullable fields marked with `| null`.

**Downstream**: S11–S18 states, `pr-review`, `pr-merge`, `review-fix`.

### Target 5: `evidence-issue`

**Purpose**: Issue metadata for prioritization and dependency analysis.

**Input**: `gh` REST API. Optional `ISSUE=<number>` argument; without it, returns all open Issues.

**Output schema**:

```json
{
  "issues": [
    {
      "number": "integer",
      "title": "string",
      "labels": ["string"],
      "has_test_plan": "boolean",
      "has_acceptance_criteria": "boolean",
      "blocked_by": ["integer"],
      "blocks": ["integer"],
      "is_parent": "boolean",
      "assignee": "string | null",
      "created_at": "ISO8601"
    }
  ],
  "dependency_graph": {
    "roots": ["integer"],
    "leaves": ["integer"],
    "depth": "integer"
  },
  "timestamp": "ISO8601"
}
```

**Field semantics**:

- `is_parent`: true if Issue has sub-issues (detected via checkbox list or "Sub-issues" section)
- `blocked_by` / `blocks`: extracted from Issue body dependency references
- `dependency_graph.roots`: Issues with no blockers (can start immediately)
- `dependency_graph.leaves`: Issues that block nothing
- `dependency_graph.depth`: maximum dependency chain length

**Nullability**: all fields required. `assignee` nullable. Arrays may be empty.

**Downstream**: S02 (PreFlightReview), S03 (ReadyToStart) Issue selection, `implement` auto-select.
