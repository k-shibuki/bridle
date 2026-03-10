# Cursor AI Configuration

This directory contains the AI development system for bridle, organized into two domains: **Design** and **Controls**. Two AI agents operate on this repository: **Cursor** (implementation and review) and **Codex Cloud** (automated PR review).

## AI Development System

```
AI Development System
├── Design (what & why)
│   ├── ADRs          docs/adr/
│   └── Schemas       docs/schemas/
│
└── Controls (how)
    ├── Rules          .cursor/rules/        ← policy
    ├── Commands       .cursor/commands/     ← procedure
    ├── Knowledge      .cursor/knowledge/    ← reference
    ├── Guards         hooks, CI, BP         ← enforcement
    └── Surface        Makefile, README, …   ← entry point
```

**Design** records architectural decisions (ADRs) and data contracts (schemas). Design documents are immutable once accepted and carry architectural authority — implementation must be consistent with them. Deviating from an ADR requires a new ADR that supersedes it.

**Controls** govern the development process:

| Component | Location | Content | Enforcement |
|---|---|---|---|
| **Rules** | `.cursor/rules/*.mdc` | MUST / MUST NOT policies | Hard stop on violation |
| **Commands** | `.cursor/commands/*.md` | Step-by-step procedures | No step skipping |
| **Knowledge** | `.cursor/knowledge/*.md` | Patterns, playbooks, reference | Advisory (referenced by rules/commands) |
| **Guards** | `.pre-commit-config.yaml`, `.github/workflows/*.yaml`, `tools/` | Hooks, CI, Branch Protection | Deterministic (tool-enforced) |
| **Surface** | `Makefile`, `README.md`, `.github/CONTRIBUTING.md`, `.github/ISSUE_TEMPLATE/` | Entry points, development API | Discovery / onboarding |

### Codex Cloud Integration

Codex Cloud Review operates as an external PR reviewer via `AGENTS.md` (repo root). The Cursor agent **actively orchestrates** Codex reviews — automatic review is OFF, and the agent triggers Codex explicitly via `@codex review` when needed.

**Active orchestration model**: The agent decides whether Codex review is needed (based on change type), triggers it, delegates the wait to a background subagent, and integrates findings into `pr-review`. See `codex--review-lifecycle.md` for the SSOT on Codex behavior.

```
AGENTS.md (Codex entry point — in .cursorignore, invisible to Cursor)
  ├── Review guidelines (P0/P1 severity — stable base criteria)
  └── References:
      ├── .cursor/rules/knowledge-index.mdc  ← shared lookup table
      ├── .cursor/knowledge/codex--review-lifecycle.md  ← Codex behavior SSOT
      ├── .cursor/knowledge/review--*.md     ← feedback loop accumulates here
      ├── .cursor/commands/pr-review.md      ← review procedure
      └── .cursor/commands/review-fix.md     ← fix procedure
```

- **Cursor** reads `.cursor/` directly via rules, commands, knowledge
- **Codex** reads `AGENTS.md` first, then follows references into `.cursor/` files
- **Active trigger**: Agent triggers Codex via `@codex review` comment in `pr-create` Step 5 or `review-fix` Step 5b. Wait is delegated to background subagents (Template 4/5 in `agent--delegation-templates.md`)
- **Feedback loop**: recurring false positives become knowledge atoms (`review--*.md`), benefiting both agents
- **Drift detection**: `make review-sync-check` verifies that `AGENTS.md` and `pr-review.md` cover the same review categories (enforced in CI)

**Domain relationships**: Design constrains Controls — implementation choices must follow accepted ADRs. Within Controls: Rules declare policies; Guards enforce them deterministically. Commands define procedures constrained by Rules and referencing Knowledge. Surface provides entry points for both human and AI workflows. Each piece of information exists in exactly one place (Single Source of Truth).

The individual elements — ADRs, schemas, rule files, command specs, knowledge atoms, guard configs, and surface assets — are collectively called **controls**. The `controls-review` command audits these controls for structural integrity.

## Design: ADRs and Schemas

### Architecture Decision Records (`docs/adr/`)

ADRs document significant architectural decisions, their context, and trade-offs.

**Format**: Each ADR is a Markdown file named `NNNN-short-title.md` where NNNN is a zero-padded sequence number.

**Template**:

```markdown
# ADR-NNNN: Title

## Context

What is the issue that we're seeing that is motivating this decision?

## Decision

What is the change that we're proposing and/or doing?

## Consequences

What becomes easier or more difficult because of this change?
```

**Workflow**:

1. Create a new ADR when making a significant architectural decision.
2. Use the next sequence number (e.g., `0010` after `0009`).
3. Reference ADRs from code comments only when the decision directly affects the implementation.

**References**: [Michael Nygard's ADR article](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions), [ADR GitHub organization](https://adr.github.io/)

### YAML Schemas (`docs/schemas/`)

These YAML schema files define the structure of plugin artifacts (decision graph, knowledge entries, constraints, context schema, decision log) during the design phase.

**Canonical Source of Truth**: Once implemented, **S7 class definitions in bridle core become the canonical source of truth** (see [ADR-0001](../docs/adr/0001-use-s7-class-system.md)). These YAML schemas serve as design-phase aids and will be kept in sync with the S7 classes or deprecated once the implementation stabilizes. Production validation is handled by S7 property validators; YAML schema validation is optional (for design support purposes).

| File | Describes | Related ADR |
|---|---|---|
| `decision_graph.schema.yaml` | Decision graph structure (nodes, transitions, policies, template ref) | [ADR-0002](../docs/adr/0002-decision-graph-flow-control.md), [ADR-0005](../docs/adr/0005-graph-policy-layer.md), [ADR-0009](../docs/adr/0009-graph-template-composition.md) |
| `knowledge.schema.yaml` | Knowledge entry format (when, computable_hint, properties) | [ADR-0003](../docs/adr/0003-when-condition-semantics.md) |
| `constraints.schema.yaml` | Technical constraint format (forces, requires, valid_values, confidence) | [ADR-0004](../docs/adr/0004-scanner-three-layer-analysis.md), [ADR-0008](../docs/adr/0008-scanner-resilience.md) |
| `context_schema.schema.yaml` | Variable scope for computable_hint (static declarations + data expectations) | [ADR-0007](../docs/adr/0007-context-variable-scope.md) |
| `decision_log.schema.yaml` | Decision audit log entry format (JSONL) | [ADR-0006](../docs/adr/0006-decision-audit-log.md) |

Each schema file contains both the schema definition and a concrete example based on `meta::metabin`.

## Project Knowledge Map

Start here to find the right information quickly.

| What you need | Where to look |
|---------------|---------------|
| What bridle is, architecture, tech stack | [`README.md`](../README.md) (root) |
| ADRs (design decisions) | [`docs/adr/`](../docs/adr/) — format and workflow above |
| YAML schemas (data contracts) | [`docs/schemas/`](../docs/schemas/) — file table above |
| S7 class implementations | `R/` |
| Subagent delegation policy | `subagent-policy.mdc` |
| **Any specific pattern/gotcha** | **`knowledge-index.mdc`** — trigger-keyword lookup for all atoms and ADRs |
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
| Contributing (human-readable) | [`.github/CONTRIBUTING.md`](../.github/CONTRIBUTING.md) |
| Open Issues / next tasks | `gh issue list --state open` |
| Development status / phases | [`README.md` § Development Status](../README.md#development-status) |

### Reading Order for AI Agents

1. **This file** — understand the system structure, workflow, and available commands
2. **`knowledge-index.mdc`** — understand available knowledge atoms and ADRs (always loaded)
3. **`gh issue list --state open`** — see what needs doing
4. **Relevant ADR(s)** — before implementing a feature (check Issue body for governing ADRs)
5. **`R/`** — check existing patterns (if any code exists)

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
                                                  commit → pr-create → [Codex trigger + CI] → pr-review → review-fix (if needed) → pr-merge
```

When CI is pending, `next` always delegates CI-wait to a background subagent (see `subagent-policy.mdc`). The main agent proceeds with independent Issues or housekeeping. After CI passes, `pr-review` runs before merge:

```
                         ┌──────────────────────────────────────────────┐
                         │  Background subagent (fast)                  │
pr-create → [CI pending] ┤  CI poll → report                           │
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

Two exception types exist, with different delivery methods (see `workflow-policy.mdc` § Exception Policy for the full contract):

#### hotfix (critical production fix → exception PR)

```
doctor → implement → quality-check → test-regression → docs-discover (Mode 2) → commit → pr-create (exception path) → [CI] → pr-review → pr-merge
```

Use when: main is broken, users are blocked, or CI is non-functional. Issue not required, but must be justified in PR body. **All code changes go through PR — direct push to main is never permitted.**

#### no-issue (justified exception → exception PR or direct push)

```
doctor → implement → quality-check → test-regression → docs-discover (Mode 2) → commit → pr-create (exception path) → [CI] → pr-review → pr-merge
```

Use when: justified exception (e.g., meta-implementation of workflow, documentation-only change). Issue not required, but must be justified in PR body. **Documentation-only changes** (type: `docs`) may use direct push to `main` instead of the PR flow.

## Commands

| Phase | Command | Purpose |
|-------|---------|---------|
| **Meta** | **`next`** | **Assess state, propose next action, drive workflow autonomously** |
| Planning | `doctor` | Check development environment |
| Planning | `issue-create` | Create GitHub Issue with spec, DoD, and test plan |
| Planning | `issue-review` | Review open Issues for quality, consistency, and implementability |
| Planning | `controls-review` | Audit AI development system for reference integrity, SSOT/DRY, contradictions |
| Development | `implement` | Select next Issue (or specify one) and write code (no tests) |
| Development | `scaffold-class` | Generate S7 class from YAML schema |
| Development | `test-create` | Design and implement tests |
| Development | `integration-design` | Design cross-module integration |
| Quality | `quality-check` | lint + format + R CMD check + schema validation |
| Quality | `test-regression` | Run tests (scoped then full) + coverage gate |
| Docs | `docs-discover` | Find (Mode 1) and update (Mode 2) related docs |
| Git | `commit` | Create git commits (+ docs direct push via `no-issue` exception) |
| Git | `pr-create` | Create feature branch + PR (with `Closes #<issue>`) |
| Git | `pr-review` | Review PR (Cursor + Codex findings) and produce merge recommendation |
| Git | `review-fix` | Address review findings from `pr-review`, re-push for re-review |
| Git | `pr-merge` | Execute merge (GitHub or local) |
| Knowledge | `knowledge-create` | Capture new pattern/gotcha as atomic knowledge file |
| Knowledge | `session-retro` | Reflect on session activity, extract learnings, propose control system improvements |
| Debug | `debug` | Hypothesis-driven debugging |

## Rules

Rules define enforceable MUST/MUST NOT policies. Commands define procedures. Knowledge provides advisory patterns. Guards enforce Rules deterministically via hooks and CI. Surface provides entry points and development APIs. Design records architectural decisions that constrain all of the above.

| Rule | Scope | Related Knowledge |
|------|-------|-------------------|
| `coding-policy.mdc` (always) | Core coding assistance | — |
| `agent-safety.mdc` (always) | Hard Stops — absolute prohibitions | — |
| `workflow-policy.mdc` (always) | Issue-driven workflow, exception policy, knowledge consultation triggers | — |
| `knowledge-index.mdc` (always) | Trigger-keyword lookup for all knowledge atoms and ADRs | All atoms in `.cursor/knowledge/` + `docs/adr/` |
| `subagent-policy.mdc` | Subagent delegation, Two-Tier Gate, CI polling | `agent--*` atoms, `git--*` atoms, `ci--*` atoms |
| `quality-policy.mdc` | Lint/format/check, S7 type strictness, schema-code consistency, verification gates | `lint--*` atoms, `r--*` atoms |
| `test-strategy.mdc` | Test design and review | `test--*` atoms, `r--null-assignment-trap.md` |
| `debug-strategy.mdc` | Debugging methodology | `debug--*` atoms |
| `integration-strategy.mdc` | Cross-module design | — |
| `commit-format.mdc` | Commit message format, branch naming | — |

## Issue-Driven Workflow Principles

See `workflow-policy.mdc` § Issue-Driven Workflow for the full policy. Key principles: every task starts as an Issue, 1 Issue ≈ 1 PR, traceability is mandatory, exceptions are explicit, and blocking operations are delegated to subagents (see `subagent-policy.mdc`).
