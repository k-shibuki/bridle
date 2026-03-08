# Contributing to bridle

## Setup

See the [Development Environment](README.md#development-environment) section in the README.

```bash
make container-build
make container-up
make renv-init
make doctor          # Verify everything works
```

## Issue-Driven Workflow

All changes follow an **Issue-driven workflow**. Every task starts as a GitHub Issue and results in a PR that closes it.

### For AI Agents

The full AI workflow (commands, rules, knowledge map) is documented in [`.cursor/README.md`](.cursor/README.md). The standard flow is:

```
doctor → issue-create → implement → test-create → quality-check
  → regression-test → docs-discover → commit → pr-create → [CI] → pr-review → pr-merge
```

### For Human Contributors

1. Pick an open Issue (or create one via `gh issue create`)
2. Create a feature branch: `git checkout -b feat/<issue>-<description>`
3. Implement, test, and verify quality (see Make targets below)
4. Commit with `Refs: #<issue>` in the footer
5. Open a PR with `Closes #<issue>` in the body

## Coding Standards

- **S7 classes**: follow [ADR-0001](docs/adr/0001-use-s7-class-system.md). All properties must have explicit types; `class_any` is prohibited.
- **Lint**: configured in [`.lintr`](.lintr). Run `make lint` to check, `make format` to auto-fix formatting.
- **Quality gate**: `make check` must pass with 0 errors, 0 warnings, 0 notes.

## Make Targets

Run `make help` for all available commands.

| Step | Command |
|------|---------|
| Check environment | `make doctor` |
| Run tests | `make test` |
| Lint | `make lint` |
| Format | `make format` |
| Full CI locally | `make ci` |
| R CMD check | `make check` |

## Commits

Follow [Conventional Commits](https://www.conventionalcommits.org/) format. Messages in English. See [commit message rules](.cursor/rules/commit-format.mdc) for details.

## Pull Requests

Use the [PR template](.github/PULL_REQUEST_TEMPLATE.md). All CI checks must pass before merge.
