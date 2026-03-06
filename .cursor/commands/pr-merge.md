# pr-merge

## Purpose

Execute a merge — either via GitHub (for PR flow) or locally (for exception flow).

## When to use

- After `pr-review` concludes "Mergeable" (standard PR flow)
- After `commit` and successful quality/tests (exception flow: hotfix/docs-only on local branch)

## Inputs

- PR number (for GitHub merge) or branch name (for local merge) (required)
- Merge strategy: squash or merge (required)

## High-risk change policy

Changes to the following areas require extra caution before merge:

| Area | Examples | Policy |
|------|----------|--------|
| Schema / S7 contracts | `docs/schemas/**`, `R/*` (S7 classes) | Verify schema-code consistency |
| CI / build pipeline | `.github/workflows/**`, `Makefile`, `tools/**` | Verify `make ci` passes locally |
| AI agent rules | `.cursor/rules/**`, `.cursor/commands/**` | Review all downstream impact |
| Security-related | Auth, data retention, network boundaries | Require explicit user approval |

For solo development, the AI agent should flag these areas and confirm with the user before merging. In team settings, consider requiring 2 reviewers for high-risk areas via branch protection rules.

## Merge strategy selection

| Source | Pattern | Strategy |
|--------|---------|----------|
| Local human work | 2-5 meaningful commits | merge (preserves history) |
| AI agent (Claude Code, Cursor) | Many micro-commits | **squash** (consolidates) |
| Mixed/uncertain | Review with `git log` | Case-by-case |

**Decision heuristic**:

```bash
# For PRs
gh pr view <PR-number> --json commits --jq '.commits | length'

# For local branches
git log main..<branch> --oneline | wc -l
```

- 2-5 well-organized commits -> merge
- 10+ commits, or "wip"/"fix typo" chains -> squash

## GitHub PR merge (standard PR flow)

Merge only after CI passes and review is complete.

```bash
# Squash merge (consolidates commits)
gh pr merge <PR-number> --squash --delete-branch

# Normal merge (preserves history)
gh pr merge <PR-number> --merge --delete-branch
```

After merge, update local main:

```bash
git checkout main
git pull origin main
```

## Local merge (exception flow only)

For hotfix/docs-only changes that bypassed the PR flow:

### Normal merge

```bash
git checkout main
git merge --no-edit <branch-name>
```

### Squash merge

```bash
git checkout main
git merge --squash <branch-name>
git commit -m "<type>: <description>

Refs: #<issue-number>"
```

After `--squash`, you must run `git commit` with a message following `commit-message-format.mdc`.

## Constraints

- Use non-interactive git flags (`--no-edit`, `--no-pager`) to avoid hangs.
- Do not merge if CI has failures or warnings remain.
- **Approval model**: Merge is permitted when one of the following is satisfied:
  - `pr-review` concluded "Mergeable"
  - Explicit user instruction to merge

## Output (response format)

- **Method**: GitHub PR merge / local merge
- **Strategy**: squash / merge
- **Result**: success / conflicts
- **Commit(s)**: resulting commit hash(es)
- **Issue**: `#<number>` closed by this merge (if applicable)
- **Notes**: any conflicts and how they were resolved

## Related

- `@.cursor/commands/pr-review.md` (previous step in PR flow)
- `@.cursor/commands/push.md` (exception flow: hotfix/docs-only)
- `@.cursor/rules/commit-message-format.mdc` (for squash commit messages)
