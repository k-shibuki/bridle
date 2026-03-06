# Cursor AI Configuration

This directory contains rules (policies) and commands (procedures) for AI-assisted development of bridle.

## Project Knowledge Map

Start here to find the right information quickly.

| What you need | Where to look |
|---------------|---------------|
| What bridle is, architecture, tech stack | [`README.md`](../README.md) (root) |
| ADRs (design decisions) | [`docs/adr/`](../docs/adr/) — referenced from [`docs/README.md`](../docs/README.md) |
| YAML schemas (data contracts) | [`docs/schemas/`](../docs/schemas/) — referenced from [`docs/README.md`](../docs/README.md) |
| S7 class implementations | `R/` (empty until first implementation) |
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

- **`next`** can be invoked at any point to assess the current state and propose the appropriate next command. After approval, it delegates to the command and loops back for the next step.
- `implement` auto-selects the next Issue when no Issue number is provided (analyzes dependencies, priority, and blocked status).
- `docs-discover` runs twice: **Mode 1** during `implement` (early discovery) and **Mode 2** before `commit` (apply doc updates).

Use for: all feature work, bug fixes, refactors, and multi-file changes.

### Exception Flow (main direct, restricted)

```
doctor → implement → quality-check → regression-test → docs-discover (Mode 2) → commit → push
```

Use **only** for: `hotfix` (critical production fixes) or `docs-only` (documentation-only changes with no code impact). Must be justified in the commit message.

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
| Git | `push` | Push main to origin (**exception flow only**) |
| Debug | `debug` | Hypothesis-driven debugging |

## Rules

Rules define policies; commands define procedures.

| Rule | Scope | Commands |
|------|-------|----------|
| `v5_bridle.mdc` (always) | Core coding assistance | All |
| `ai-guardrails.mdc` (always) | AI safety checks, Issue-driven workflow, schema-code consistency | `doctor`, `issue-create`, `implement`, `quality-check`, `pr-create`, `docs-discover` |
| `test-strategy.mdc` | Test design and review | `test-create`, `test-review` |
| `integration-design.mdc` | Cross-module design | `integration-design` |
| `debug.mdc` | Debugging methodology | `debug` |
| `quality-check.mdc` | Lint/format/check policy | `quality-check`, `validate-schemas` |
| `commit-message-format.mdc` | Commit message format, branch naming | `commit`, `pr-create` |

## Issue-Driven Workflow Principles

1. **Every task starts as an Issue**: Use `issue-create` to decompose tasks and create structured GitHub Issues.
2. **1 Issue ≈ 1 PR**: Each Issue should be implementable in a single PR. Large tasks are split into child Issues.
3. **Traceability is mandatory**: PRs must reference their Issue (`Closes #N`), commits should reference it (`Refs: #N`).
4. **No main direct push** for normal changes: All code changes go through the PR flow with CI validation.
5. **Exceptions are explicit**: `hotfix` and `docs-only` changes may bypass the PR flow but must justify the exception.
