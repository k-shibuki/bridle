# Contributing to bridle

## Setup

See the [Development Environment](README.md#development-environment) section in the README.

```bash
make container-build
make container-start
make package-init
make git-install-hooks   # Install git hooks (pre-commit, pre-push, commit-msg)
make doctor              # Verify everything works
```

## Issue-Driven Workflow

All changes follow an **Issue-driven workflow**. Every task starts as a GitHub Issue and results in a PR that closes it.

### For AI Agents

The full AI workflow is documented in [`docs/agent-control/`](../docs/agent-control/). The standard flow is:

```
doctor → issue-create → implement → test-create → verify
  → commit → pr-create → [CI] → pr-review → review-fix → pr-merge
```

### For Human Contributors

Follow the same Issue-driven flow: pick an Issue, branch, implement, commit (with `Refs: #<issue>`), and open a PR (with `Closes #<issue>`). See [commit rules](.cursor/rules/commit-format.mdc) for branch naming and message format.

## Coding Standards

- **S7 classes**: follow [ADR-0001](docs/adr/0001-use-s7-class-system.md). See [quality-policy.mdc](.cursor/rules/quality-policy.mdc) § Type Strictness (S7) for type requirements.
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
| Full quality gate | `make gate-quality` |
| R CMD check | `make check` |

## Commits

Follow [Conventional Commits](https://www.conventionalcommits.org/) format. Messages in English. See [commit message rules](.cursor/rules/commit-format.mdc) for details.

## Pull Requests

Use the [PR template](.github/PULL_REQUEST_TEMPLATE.md). All CI checks must pass before merge.
