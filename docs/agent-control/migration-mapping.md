# Migration Mapping: Procedural Commands → Agent Control System

> **This document is valid only during the migration period (Issue #228).**
> Delete this file after all implementation issues are complete.

## Paradigm shift

**Old**: Control via procedural specification — give the agent detailed
steps, hoping compliance induces correct behavior. Observation, judgment,
and execution mixed in every command. Edge cases caused drift; adding more
steps increased contradiction.

**New**: Control via information-space design — structure the information
presented to the agent (evidence, invariants, knowledge) so that the LLM's
own reasoning operates within a well-constrained space. The agent sees
state, not instructions for how to determine state.

## Makefile target renaming (planned; not yet implemented)

Complete mapping from current target names to planned names for the
migration. These names are **design targets for Issue #228**, not the
current CLI surface.

| Current name | Planned name | Category | Change rationale |
|----------|----------|----------|-----------------|
| `help` | `help` | meta | — |
| `clean` | `clean` | meta | — |
| `status` | `status` | meta | — |
| `container-build` | `container-build` | container | — |
| `container-up` | `container-start` | container | Verb clarity: `start`/`stop` pair |
| `container-down` | `container-stop` | container | Verb clarity: `start`/`stop` pair |
| `container-shell` | `container-shell` | container | — |
| `rstudio` | `container-rstudio` | container | Group with container targets |
| `renv-init` | `package-init` | package | No tool name in target |
| `renv-restore` | `package-restore` | package | No tool name in target |
| `renv-snapshot` | `package-snapshot` | package | No tool name in target |
| `renv-check` | `package-sync-verify` | package | `verify` not `check`; describes what it verifies |
| `install` | `package-install` | package | Group with package targets |
| `lint` | `lint` | quality | Short, universally understood |
| `lint-json` | `lint-json` | quality | — |
| `changed-lint` | `lint-changed` | quality | Modifier as suffix |
| `format` | `format` | quality | — |
| `format-check` | `format-verify` | quality | `verify` not `check` |
| `check` | `check` | quality | R CMD check (reserved meaning) |
| `check-fast` | `check-quick` | quality | Clearer adjective |
| `test` | `test` | quality | — |
| `test-json` | `test-junit` | quality | Actual output format (JUnit XML) |
| `changed-test` | `test-changed` | quality | Modifier as suffix |
| `coverage` | `coverage` | quality | — |
| `coverage-check` | `coverage-verify` | quality | `verify` not `check` |
| `validate-schemas` | `schema-validate` | quality | Category-action order |
| `review-sync-check` | `review-sync-verify` | quality | `verify` not `check` |
| `document` | `document` | documentation | — |
| `site` | `site-build` | documentation | Add verb |
| `ci-fast` | `gate-fast` | gate | Descriptive gate hierarchy |
| `ci` | `gate-quality` | gate | Describes what it gates (full quality) |
| `ci-pr` | `gate-pull-request` | gate | No abbreviation |
| `pr-ready` | `gate-full` | gate | Highest gate level |
| `doctor` | `doctor` | environment | Well-known term |
| `doctor-json` | `doctor-json` | environment | — |
| `kb-manifest` | `knowledge-manifest` | knowledge | No abbreviation |
| `kb-validate` | `knowledge-validate` | knowledge | No abbreviation |
| `kb-new` | `knowledge-new` | knowledge | No abbreviation |
| `install-hooks` | `git-install-hooks` | git | Group with git targets |
| `new-branch` | `git-new-branch` | git | Group with git targets |
| `git-post-merge-cleanup` | `git-post-merge-cleanup` | git | New target (already uses planned name) |
| `scaffold-class` | `scaffold-class` | scaffold | — |
| `scaffold-test` | `scaffold-test` | scaffold | — |

## Coverage guarantee table

This table maps every observation from the old command files to an
evidence target, proving no observation is lost in the transition.

| Old observation | Old command(s) | Evidence target | Field path |
|-----------------|---------------|-----------------|------------|
| `git branch --show-current` | next, commit, pr-create | `evidence-workflow-position` | `git.branch` |
| `git status --short` | next, commit, pr-create | `evidence-workflow-position` | `git.uncommitted_files` |
| `git log --oneline` | next, commit, session-retro | Not evidence (historical) | Use `git` directly |
| `git diff --stat` / `git diff` | commit, implement | Not evidence (content) | Use `git` directly |
| Stale branch detection | next | `evidence-workflow-position` | `git.stale_branches` |
| `git stash list` | subagent signal scan | `evidence-workflow-position` | `git.stash_count` |
| `gh issue list` | next, implement, issue-review | `evidence-issue` | `issues[]` |
| `gh issue view <N>` | implement, pr-review, issue-review | `evidence-issue` | `issues[]` (filtered) |
| `gh pr list --state open` | next | `evidence-workflow-position` | `pull_requests.open[]` |
| `gh pr list --state merged` | next | `evidence-workflow-position` | `pull_requests.recently_merged[]` |
| `gh pr view --json checks` | pr-review, pr-merge | `evidence-pull-request` | `ci.checks[]` |
| `gh pr view --json mergeable` | pr-merge, next | `evidence-pull-request` | `merge.mergeable` |
| `gh pr view --json mergeStateStatus` | pr-merge | `evidence-pull-request` | `merge.merge_state_status` |
| `gh pr diff` | pr-review | Not evidence (content) | Use `gh` directly |
| `gh api pulls/<N>/reviews` | pr-review, pr-merge | `evidence-pull-request` | `reviews.*` |
| `gh api pulls/<N>/comments` | pr-create, review-fix | `evidence-pull-request` | `reviews.bot_*` |
| GraphQL review threads | next, review-fix | `evidence-pull-request` | `reviews.threads_*` |
| `make doctor` / `make doctor-json` | next, doctor, verify | `evidence-environment` | all fields |
| `make format` / `make format-check` | verify | Not evidence (action) | Remains as quality target |
| `make lint` / `make lint-json` | verify | `evidence-lint` | all fields |
| `make test` | verify | Not evidence (action) | Remains as quality target |
| `make check` | verify | Not evidence (action) | Remains as quality target |
| `make coverage-check` | verify | Not evidence (action) | Remains as quality target |
| `make validate-schemas` | verify | Not evidence (action) | Remains as quality target |
| `make kb-validate` | verify | Not evidence (action) | Remains as quality target |
| `gh auth status` | pr-create | Not evidence (precondition) | Guard: check in Procedure |
| `gh api repos/.../protection` | pr-merge, controls-review | Not evidence (configuration) | Remains in Procedure |
| Subagent transcript check | next | Not evidence (agent-internal) | Remains agent-internal |
| `.git/hooks/` existence | doctor, pr-merge | `evidence-environment` | `checks[]` where `name == "git_hooks"` |
| `DESCRIPTION` / `renv.lock` reads | scaffold-class, integration-design | Not evidence (source content) | Use `Read` directly |
| `R/` and `tests/` source reads | implement, test-create, pr-review | Not evidence (source content) | Use `Read` directly |

## Coverage rules

- **Structured observation** (state queries): MUST be covered by an evidence target
- **Content reads** (source code, diffs, Issue bodies): remain direct reads — they are inputs to reasoning, not state signals
- **Actions** (format, lint, test, check): remain as quality targets — they modify or verify, not observe
- **Configuration reads** (Branch Protection settings): remain in Procedure — infrequent and configuration-specific
- **Agent-internal** (subagent transcripts): remain agent-internal — not project state
