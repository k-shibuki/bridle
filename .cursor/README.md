# Cursor AI Configuration

This directory contains the AI control system for bridle development, organized into three layers.

## Three-Layer Control System

| Layer | Location | Content | Enforcement |
|---|---|---|---|
| **Rules** | `.cursor/rules/*.mdc` | MUST / MUST NOT policies | Hard stop on violation |
| **Commands** | `.cursor/commands/*.md` | Step-by-step procedures | No step skipping |
| **Knowledge** | `.cursor/knowledge/*.md` | Patterns, playbooks, reference | Advisory (referenced by rules/commands) |

**Hierarchy**: Rules constrain commands; commands reference knowledge. No reverse dependencies. Each piece of information exists in exactly one place (Single Source of Truth).

## Project Knowledge Map

Start here to find the right information quickly.

| What you need | Where to look |
|---------------|---------------|
| What bridle is, architecture, tech stack | [`README.md`](../README.md) (root) |
| ADRs (design decisions) | [`docs/adr/`](../docs/adr/) — referenced from [`docs/README.md`](../docs/README.md) |
| YAML schemas (data contracts) | [`docs/schemas/`](../docs/schemas/) — referenced from [`docs/README.md`](../docs/README.md) |
| S7 class implementations | `R/` |
| Subagent delegation policy | `ai-guardrails.mdc` § Subagent Delegation |
| Subagent prompt templates | `knowledge/subagent-prompts.md` |
| Lint/format patterns (S7, styler/lintr) | `knowledge/r-lint-patterns.md` |
| R testing gotchas (mocks, NULL trap) | `knowledge/r-testing-patterns.md` |
| R debugging tools and templates | `knowledge/r-debugging-patterns.md` |
| CI job dependencies and polling strategy | `knowledge/ci-pipeline.md` |
| Git recovery playbooks | `knowledge/git-recovery.md` |
| Development workflow + commands | This file (below) |
| Command details (procedures) | `.cursor/commands/*.md` |
| Policy rules | `.cursor/rules/*.mdc` |
| CI/CD pipeline | [`.github/workflows/`](../.github/workflows/) |
| Makefile targets | `make help` or [`Makefile`](../Makefile) |
| Container setup | [`containers/`](../containers/) + `make doctor` |
| Contributing (human-readable) | [`CONTRIBUTING.md`](../CONTRIBUTING.md) |
| Open Issues / next tasks | `gh issue list --state open` |
| Development status / phases | [`README.md` § Development Status](../README.md#development-status) |

### Reading Order for New AI Agents

1. **This file** — understand the workflow and available commands
2. **`gh issue list --state open`** — see what needs doing
3. **`docs/README.md`** — understand ADRs and schemas
4. **Relevant ADR(s)** — before implementing a feature
5. **`R/`** — check existing patterns (if any code exists)

## Development Workflow (Issue-Driven)

All changes follow an **Issue-driven workflow**. Every implementation task starts with a GitHub Issue and ends with a PR that closes it.

### Standard Flow (PR-based)

```
doctor → issue-create → implement ─────────→ test-create → quality-check
                          │                                      │
                     docs-discover                          regression-test
                      (Mode 1:                                   │
                      Discover)                             docs-discover
                                                             (Mode 2:
                                                              Update)
                                                                 │
                                                  commit → pr-create → [CI] → pr-review → pr-merge
```

When CI is pending and independent work exists, `next` delegates the CI-wait + merge to a background subagent and starts the next Issue in parallel:

```
                         ┌──────────────────────────────────────────────┐
                         │  Background subagent (fast)                  │
pr-create → [CI pending] ┤  CI poll → merge → rebase next → CI poll... │
                         └──────────────────────────────────────────────┘
                         │
            Main agent   │  implement (next Issue) → test-create → ...
                         │
                         └→ next re-assessment checks subagent transcript
```

- **`next`** can be invoked at any point to assess the current state and propose the appropriate next command. After approval, it delegates to the command and loops back for the next step. When blocking operations (CI polling) are detected, `next` delegates them to background subagents (see `ai-guardrails.mdc` § Subagent Delegation).
- `implement` auto-selects the next Issue when no Issue number is provided (analyzes dependencies, priority, and blocked status).
- `docs-discover` runs twice: **Mode 1** during `implement` (early discovery) and **Mode 2** before `commit` (apply doc updates).

Use for: all feature work, bug fixes, refactors, and multi-file changes.

### Exception Flow (restricted)

Two exception types exist, with different delivery methods:

#### hotfix (critical production fix → exception PR)

```
doctor → implement → quality-check → regression-test → docs-discover (Mode 2) → commit → pr-create (exception path) → [CI] → pr-review → pr-merge
```

Use when: main is broken, users are blocked, or CI is non-functional. Issue not required, but must be justified in PR body. **All code changes go through PR — direct push to main is never permitted.**

#### docs-only (documentation change → direct push)

```
doctor → implement → commit → push
```

Use when: change is documentation only (README, ADR, comments, Cursor rules/commands text) with no code impact. May also use a PR if preferred.

## Commands

| Phase | Command | Purpose |
|-------|---------|---------|
| **Meta** | **`next`** | **Assess state, propose next action, drive workflow autonomously** |
| Planning | `doctor` | Check development environment |
| Planning | `issue-create` | Create GitHub Issue with spec, DoD, and test plan |
| Development | `implement` | Select next Issue (or specify one) and write code (no tests) |
| Development | `scaffold-class` | Generate S7 class from YAML schema |
| Development | `test-create` | Design and implement tests |
| Development | `test-review` | Review test quality |
| Development | `integration-design` | Design cross-module integration |
| Quality | `quality-check` | lint + format + R CMD check |
| Quality | `regression-test` | Run tests (scoped then full) |
| Quality | `validate-schemas` | Validate YAML schemas |
| Docs | `docs-discover` | Find (Mode 1) and update (Mode 2) related docs |
| Git | `commit` | Create git commits (with `Refs: #<issue>`) |
| Git | `pr-create` | Create feature branch + PR (with `Closes #<issue>`) |
| Git | `pr-review` | Review PR and produce merge recommendation |
| Git | `pr-merge` | Execute merge (GitHub or local) |
| Git | `push` | Push main to origin (**docs-only exception only**) |
| Debug | `debug` | Hypothesis-driven debugging |

## Rules

Rules define enforceable MUST/MUST NOT policies. Commands define procedures. Knowledge provides advisory patterns.

| Rule | Scope | Related Knowledge |
|------|-------|-------------------|
| `v5_bridle.mdc` (always) | Core coding assistance | — |
| `ai-guardrails.mdc` (always) | AI safety, Issue workflow, subagent delegation | `subagent-prompts.md`, `git-recovery.md`, `ci-pipeline.md` |
| `test-strategy.mdc` | Test design and review | `r-testing-patterns.md` |
| `integration-design.mdc` | Cross-module design | — |
| `debug.mdc` | Debugging methodology | `r-debugging-patterns.md` |
| `quality-check.mdc` | Lint/format/check policy | `r-lint-patterns.md` |
| `commit-message-format.mdc` | Commit message format, branch naming | — |

## Issue-Driven Workflow Principles

1. **Every task starts as an Issue**: Use `issue-create` to decompose tasks and create structured GitHub Issues.
2. **1 Issue ≈ 1 PR**: Each Issue should be implementable in a single PR. Large tasks are split into child Issues.
3. **Traceability is mandatory**: PRs must reference their Issue (`Closes #N`), commits should reference it (`Refs: #N`).
4. **No main direct push** for normal changes: All code changes go through the PR flow with CI validation.
5. **Exceptions are explicit**: `hotfix` bypasses Issue triage but still requires a PR. Only `docs-only` may use direct push to main. See `ai-guardrails.mdc` for the full policy.
6. **Parallelize via subagent delegation**: Blocking operations (CI polling, sequential merges) are delegated to background subagents so the main agent can continue independent work. See `ai-guardrails.mdc` § Subagent Delegation for the policy and `pr-merge.md` for the prompt template.
