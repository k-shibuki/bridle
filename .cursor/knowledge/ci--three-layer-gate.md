---
trigger: three-layer gate, local gate, PR gate, main gate, fail-fast, merge gate, full verification, pre-push scope, CI scope, local verification scope, gate architecture, HS-LOCAL-VERIFY scope
---
# Three-Layer Gate Architecture

Quality enforcement is distributed across three execution contexts with distinct purposes. Each layer trades off speed vs completeness.

## Layer 1: Local (fail-fast)

**Purpose**: Prevent pushing obviously broken code; save CI compute.

**Execution context**: `pre-push` Git hook (`tools/pre-push.sh`).

**Scope** (differential — only changed files):

| Change type | Checks |
|-------------|--------|
| R source (`R/`, `tests/`, `DESCRIPTION`, `NAMESPACE`) | `format-verify` + `lint-changed` + `test-changed` |
| Schemas (`docs/schemas/`, `tools/validate-schemas.R`) | `schema-validate` |
| renv (`DESCRIPTION`, `renv.lock`, `renv/`) | `package-sync-verify` |
| Knowledge base (`.cursor/knowledge/`, `.cursor/rules/knowledge-index.mdc`, `AGENTS.md` (repo root), `.cursor/commands/pr-review.md`) | `knowledge-validate` + `review-sync-verify` |
| Markdown (`**/*.md`) | `markdown-lint-changed` |

All matching change types trigger independently (no elif single-match).

**Authority**: None — bypass allowed (`SKIP_PRE_PUSH=1`). CI is the authoritative gate.

**Design principle**: Speed over completeness. Differential over full-package. Catch the obvious, let CI handle the rest.

## Layer 2: PR CI (merge gate)

**Purpose**: Enforce merge-readiness. Authoritative gate for branch protection. In addition to CI status checks (`ci-pass`, `check-policy`), GitHub Branch Protection also requires all review conversations to be resolved (`required_conversation_resolution`) before merge.

**Execution context**: `ci.yaml` on `pull_request` events.

**Scope** (full package, parallel execution):

```text
changes ──┬── schema-validate      (r_source OR schemas)
          ├── format-verify        (r_source)
          ├── lint                 (r_source)
          ├── test-unit            (r_source; BRIDLE_TEST_TIER=unit)
          ├── test-e2e             (r_source; filter e2e/integration/pipeline)
          ├── check               (r_source OR r_deps; --no-tests)
          ├── ci-config            (ci_config)
          ├── package-sync-verify  (renv_deps)
          ├── knowledge-validate   (kb_files)
          └── markdown-lint        (markdown)
                       │
                  ci-pass (required status check)
```

**Authority**: Required — `ci-pass` is a branch protection required check. PRs cannot merge without it.

**Design principle**: Completeness for the PR scope. Parallel execution for speed. No coverage (moved to Layer 3).

**Guard notes**:

- `ci-config` shellcheck is blocking (no `|| true` bypass), so shell script diagnostics now fail PR CI.
- `lint` runs `pkgload::load_all()` before `lintr::lint_package()` to align CI behavior with local lint execution and reduce cross-file false positives.

## Layer 3: Main Push (full verification)

**Purpose**: Ensure codebase-wide quality after merge. Catch cross-PR regressions.

**Execution context**: `R-CMD-check.yaml` on `push` to main.

**Scope**:

| Check | Detail |
|-------|--------|
| R CMD check | 5-matrix (macOS/Windows/Linux × R release/devel/oldrel) |
| Coverage | `covr::package_coverage()` with 80% threshold |
| Auto-Issue | Template-compliant Issue on coverage failure (with deduplication) |

**Authority**: Informational to blocking. Failures signal need for immediate remediation (auto-Issue creation). Not a merge gate — enforcement is Issue-based.

**Design principle**: Maximum coverage. Acceptable latency (not on merge critical path). Batch remediation over immediate blocking.

## Layer Interaction

```text
Developer pushes
      │
      ▼
[Layer 1: Local]  ─── fail-fast filter (seconds)
      │                bypass: SKIP_PRE_PUSH=1
      ▼
[Layer 2: PR CI]  ─── authoritative merge gate (minutes)
      │                required: ci-pass
      ▼
   PR merges
      │
      ▼
[Layer 3: Main]   ─── full verification (post-merge)
      │                enforcement: auto-Issue
      ▼
   Regression detected? → auto-Issue → batched remediation
```

**Key invariant**: Each layer is a strict superset of the previous in scope. Local catches formatting/lint for changed files. PR CI runs full lint/test/check. Main push adds OS matrix + coverage.

**Trade-off**: Coverage regressions are detected post-merge. Multiple PRs may merge before remediation. This is intentional — coverage remediation is batched for comprehensive review, not piecemeal per-PR fixes.
