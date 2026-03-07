# Cursor AI Configuration

This directory contains the AI control system for bridle development, organized into three layers.

## Three-Layer Control System

| Layer | Location | Content | Enforcement |
|---|---|---|---|
| **Rules** | `.cursor/rules/*.mdc` | MUST / MUST NOT policies | Hard stop on violation |
| **Commands** | `.cursor/commands/*.md` | Step-by-step procedures | No step skipping |
| **Knowledge** | `.cursor/knowledge/*.md` | Patterns, playbooks, reference | Advisory (referenced by rules/commands) |

**Hierarchy**: Rules constrain commands; commands reference knowledge. No reverse dependencies. Each piece of information exists in exactly one place (Single Source of Truth).

The individual components of this system — rule files, command specs, knowledge atoms, README maps, and Makefile targets — are collectively called **controls**. The `controls-review` command audits these controls for structural integrity.

## Project Knowledge Map

Start here to find the right information quickly.

| What you need | Where to look |
|---------------|---------------|
| What bridle is, architecture, tech stack | [`README.md`](../README.md) (root) |
| ADRs (design decisions) | [`docs/adr/`](../docs/adr/) — referenced from [`docs/README.md`](../docs/README.md) |
| YAML schemas (data contracts) | [`docs/schemas/`](../docs/schemas/) — referenced from [`docs/README.md`](../docs/README.md) |
| S7 class implementations | `R/` |
| Subagent delegation policy | `subagent-policy.mdc` |
| **Any specific pattern/gotcha** | **`knowledge-index.mdc`** — trigger-keyword lookup for all atoms |
| Subagent prompt templates | `knowledge/agent--delegation-templates.md` |
| Lint/format patterns (S7, styler/lintr) | `knowledge/lint--*.md` atoms |
| R testing gotchas (mocks, NULL trap) | `knowledge/test--*.md` atoms |
| R debugging tools and templates | `knowledge/debug--*.md` atoms |
| CI job dependencies and polling strategy | `knowledge/ci--*.md` atoms |
| Git recovery playbooks | `knowledge/git--*.md` atoms |
| Development workflow + commands | This file (below) |
| Command details (procedures) | `.cursor/commands/*.md` |
| Policy rules | `.cursor/rules/*.mdc` |
| Knowledge base management | `make kb-manifest`, `make kb-validate`, `make kb-new` |
| CI/CD pipeline | [`.github/workflows/`](../.github/workflows/) |
| Makefile targets | `make help` or [`Makefile`](../Makefile) |
| Container setup | [`containers/`](../containers/) + `make doctor` |
| Contributing (human-readable) | [`CONTRIBUTING.md`](../CONTRIBUTING.md) |
| Open Issues / next tasks | `gh issue list --state open` |
| Development status / phases | [`README.md` § Development Status](../README.md#development-status) |

### Reading Order for AI Agents

1. **This file** — understand the workflow and available commands
2. **`knowledge-index.mdc`** — understand available knowledge atoms (always loaded)
3. **`gh issue list --state open`** — see what needs doing
4. **`docs/README.md`** — understand ADRs and schemas
5. **Relevant ADR(s)** — before implementing a feature
6. **`R/`** — check existing patterns (if any code exists)

## Development Workflow (Issue-Driven)

All changes follow an **Issue-driven workflow**. Every implementation task starts with a GitHub Issue and ends with a PR that closes it.

### Standard Flow (PR-based)

```
doctor → issue-create → implement ─────────→ test-create → quality-check
                          │                                      │
                     docs-discover                          test-regression
                      (Mode 1:                                   │
                      Discover)                             docs-discover
                                                             (Mode 2:
                                                              Update)
                                                                 │
                                                  commit → pr-create → [CI] → pr-review → pr-merge
```

When CI is pending, `next` always delegates the CI-wait + merge to a background subagent (Hard Stop #7). The main agent proceeds with independent Issues or housekeeping:

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

- **`next`** can be invoked at any point to assess the current state and propose the appropriate next command. After approval, it delegates to the command and loops back for the next step. When blocking operations (CI polling) are detected, `next` delegates them to background subagents (see `subagent-policy.mdc`).
- `implement` auto-selects the next Issue when no Issue number is provided (analyzes dependencies, priority, and blocked status).
- `docs-discover` runs twice: **Mode 1** during `implement` (early discovery) and **Mode 2** before `commit` (apply doc updates).

Use for: all feature work, bug fixes, refactors, and multi-file changes.

### Exception Flow (restricted)

Three exception types exist, with different delivery methods (see `workflow-policy.mdc` § Exception Policy for the full contract):

#### hotfix (critical production fix → exception PR)

```
doctor → implement → quality-check → test-regression → docs-discover (Mode 2) → commit → pr-create (exception path) → [CI] → pr-review → pr-merge
```

Use when: main is broken, users are blocked, or CI is non-functional. Issue not required, but must be justified in PR body. **All code changes go through PR — direct push to main is never permitted.**

#### no-issue (justified exception → exception PR)

```
doctor → implement → quality-check → test-regression → docs-discover (Mode 2) → commit → pr-create (exception path) → [CI] → pr-review → pr-merge
```

Use when: justified exception that doesn't fit `hotfix` or `docs-only` (e.g., meta-implementation of workflow itself). Issue not required, but must be justified in PR body.

#### docs-only (documentation change → direct push)

```
doctor → implement → commit (with direct push)
```

Use when: change is documentation only (README, ADR, comments, Cursor rules/commands text) with no code impact. May also use a PR if preferred.

## Commands

| Phase | Command | Purpose |
|-------|---------|---------|
| **Meta** | **`next`** | **Assess state, propose next action, drive workflow autonomously** |
| Planning | `doctor` | Check development environment |
| Planning | `issue-create` | Create GitHub Issue with spec, DoD, and test plan |
| Planning | `issue-review` | Review open Issues for quality, consistency, and implementability |
| Planning | `controls-review` | Audit AI control system for reference integrity, SSOT/DRY, contradictions |
| Development | `implement` | Select next Issue (or specify one) and write code (no tests) |
| Development | `scaffold-class` | Generate S7 class from YAML schema |
| Development | `test-create` | Design and implement tests |
| Development | `integration-design` | Design cross-module integration |
| Quality | `quality-check` | lint + format + R CMD check + schema validation |
| Quality | `test-regression` | Run tests (scoped then full) + coverage gate |
| Docs | `docs-discover` | Find (Mode 1) and update (Mode 2) related docs |
| Git | `commit` | Create git commits (+ docs-only direct push exception) |
| Git | `pr-create` | Create feature branch + PR (with `Closes #<issue>`) |
| Git | `pr-review` | Review PR + test quality and produce merge recommendation |
| Git | `pr-merge` | Execute merge (GitHub or local) |
| Knowledge | `knowledge-create` | Capture new pattern/gotcha as atomic knowledge file |
| Knowledge | `session-retro` | Reflect on session activity, extract learnings, propose control system improvements |
| Debug | `debug` | Hypothesis-driven debugging |

## Rules

Rules define enforceable MUST/MUST NOT policies. Commands define procedures. Knowledge provides advisory patterns.

| Rule | Scope | Related Knowledge |
|------|-------|-------------------|
| `coding-policy.mdc` (always) | Core coding assistance | — |
| `agent-safety.mdc` (always) | Hard Stops — absolute prohibitions | — |
| `workflow-policy.mdc` (always) | Issue-driven workflow, exception policy, knowledge consultation triggers | — |
| `knowledge-index.mdc` (always) | Trigger-keyword lookup for all knowledge atoms | All atoms in `.cursor/knowledge/` |
| `subagent-policy.mdc` | Subagent delegation, Two-Tier Gate, CI polling | `agent--*` atoms, `git--*` atoms, `ci--*` atoms |
| `quality-policy.mdc` | Lint/format/check, S7 type strictness, schema-code consistency, verification gates | `lint--*` atoms, `r--*` atoms |
| `test-strategy.mdc` | Test design and review | `test--*` atoms, `r--null-assignment-trap.md` |
| `debug-strategy.mdc` | Debugging methodology | `debug--*` atoms |
| `integration-strategy.mdc` | Cross-module design | — |
| `commit-format.mdc` | Commit message format, branch naming | — |

## Issue-Driven Workflow Principles

1. **Every task starts as an Issue**: Use `issue-create` to decompose tasks and create structured GitHub Issues.
2. **1 Issue ≈ 1 PR**: Each Issue should be implementable in a single PR. Large tasks are split into child Issues.
3. **Traceability is mandatory**: PRs must reference their Issue (`Closes #N`), commits should reference it (`Refs: #N`).
4. **No main direct push** for normal changes: All code changes go through the PR flow with CI validation.
5. **Exceptions are explicit**: `hotfix` bypasses Issue triage but still requires a PR. Only `docs-only` may use direct push to main. See `workflow-policy.mdc` for the full policy.
6. **Parallelize via subagent delegation**: Blocking operations (CI polling, sequential merges) are always delegated to background subagents so the main agent can continue productive work (independent Issues, branch cleanup, environment health, doc review). Inline CI polling is prohibited. See `subagent-policy.mdc` for the policy and `agent--delegation-templates.md` for prompt templates.
