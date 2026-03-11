---
trigger: label taxonomy, type label, exception label, meta label, PR label, issue label, assignment rules
---
# Label Taxonomy

Every Issue and PR MUST have exactly one **type label** matching its Conventional Commits title prefix.

## Type labels (exactly one per Issue/PR)

| Label | Conventional Commits prefix | Description |
|-------|----------------------------|-------------|
| `feat` | `feat:` | New feature or capability |
| `fix` | `fix:` | Bug fix |
| `refactor` | `refactor:` | Code restructuring without behavior change |
| `perf` | `perf:` | Performance improvement |
| `docs` | `docs:` | Documentation only change |
| `test` | `test:` | Test addition or modification |
| `ci` | `ci:` | CI/CD pipeline change |
| `build` | `build:` | Build system or dependency change |
| `chore` | `chore:` | Maintenance task (no production code change) |
| `style` | `style:` | Style-only changes (formatting, no logic change) |
| `revert` | `revert:` | Revert a previous commit |

## Exception labels (zero or one per PR, additive to type label)

| Label | When to use |
|-------|-------------|
| `hotfix` | Critical fix meeting the hotfix threshold (see `workflow-policy.mdc` § fix vs hotfix Decision Criteria) |
| `no-issue` | Justified exception bypassing Issue-driven flow (includes docs-only direct push) |

Exception labels do NOT replace the type label — a PR has both (e.g., `fix` + `hotfix`). For documentation-only direct push, the combination is `docs` (type) + `no-issue` (exception).

## Meta labels (zero or more, additional context)

| Label | Description |
|-------|-------------|
| `blocked` | Issue/PR is blocked by an external dependency |
| `dependencies` | Dependabot dependency update |
| `github_actions` | Dependabot GitHub Actions update |

## Assignment rules

- `issue-create` assigns the type label at Issue creation (`--label "<type>"`).
- `pr-create` assigns the type label at PR creation (`--label "<type>"`), plus exception label if applicable.
- Policy: every Issue/PR must have exactly one recognized type label.
- Current CI enforcement: `pr-policy.yaml` validates that every PR has _at least_ one recognized type label (exact-one enforcement is a future improvement).
