# Cursor AI Configuration

This directory contains rules (policies) and commands (procedures) for AI-assisted development of bridle.

## Development Workflows

Two workflows are supported. Choose based on change scope.

### Main Direct (small changes)

```
doctor -> task-plan -> implement -> test-create -> quality-check
  -> regression-test -> commit -> push
```

Use when: single-file fixes, small refactors, documentation updates.

### Feature Branch + PR (larger changes)

```
doctor -> task-plan -> implement -> test-create -> quality-check
  -> regression-test -> commit -> pr-create -> [CI] -> pr-review -> merge
```

Use when: new features, multi-file changes, changes that benefit from CI validation.

## Commands

| Phase | Command | Purpose |
|-------|---------|---------|
| Planning | `doctor` | Check development environment |
| Planning | `task-plan` | Define scope and acceptance criteria |
| Development | `implement` | Write code (no tests) |
| Development | `scaffold-class` | Generate S7 class from YAML schema |
| Development | `test-create` | Design and implement tests |
| Development | `test-review` | Review test quality |
| Development | `integration-design` | Design cross-module integration |
| Quality | `quality-check` | lint + format + R CMD check |
| Quality | `regression-test` | Run tests (scoped then full) |
| Quality | `validate-schemas` | Validate YAML schemas |
| Git | `commit` | Create git commits |
| Git | `push` | Push main to origin (main direct flow) |
| Git | `pr-create` | Create feature branch + PR (PR flow) |
| Git | `pr-review` | Review PR + merge recommendation |
| Git | `merge` | Execute merge (GitHub or local) |
| Debug | `debug` | Hypothesis-driven debugging |
| Docs | `docs-discover` | Find and update related docs |

## Rules

Rules define policies; commands define procedures.

| Rule | Scope | Commands |
|------|-------|----------|
| `v5_bridle.mdc` (always) | Core coding assistance | All |
| `ai-guardrails.mdc` (always) | AI safety checks, schema-code consistency | `doctor`, `implement`, `quality-check`, `pr-create` |
| `test-strategy.mdc` | Test design and review | `test-create`, `test-review` |
| `integration-design.mdc` | Cross-module design | `integration-design` |
| `debug.mdc` | Debugging methodology | `debug` |
| `quality-check.mdc` | Lint/format/check policy | `quality-check`, `validate-schemas` |
| `commit-message-format.mdc` | Commit message format | `commit` |
