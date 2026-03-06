# merge

## Purpose

Execute a merge — either via GitHub (for PR flow) or locally (for main direct flow).

## When to use

- After `pr-review` recommends merge (PR flow)
- After `commit` and successful quality/tests (main direct flow, when working on a local branch)

## Inputs

- PR number (for GitHub merge) or branch name (for local merge) (required)
- Merge strategy: squash or merge (required)

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

## GitHub PR merge (recommended for PR flow)

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

## Local merge (for main direct flow)

### Normal merge

```bash
git checkout main
git merge --no-edit <branch-name>
```

### Squash merge

```bash
git checkout main
git merge --squash <branch-name>
git commit -m "<type>: <description>"
```

After `--squash`, you must run `git commit` with a message following `commit-message-format.mdc`.

## Constraints

- Use non-interactive git flags (`--no-edit`, `--no-pager`) to avoid hangs.
- Do not merge if CI has failures or warnings remain.
- **Approval model**: Merge is permitted when one of the following is satisfied:
  - Self-created PR: CI is green (called from `pr-create` Step 7)
  - External PR: `pr-review` concluded "Mergeable" (called from `pr-review` Step 6)
  - Explicit user instruction to merge

## Output (response format)

- **Method**: GitHub PR merge / local merge
- **Strategy**: squash / merge
- **Result**: success / conflicts
- **Commit(s)**: resulting commit hash(es)
- **Notes**: any conflicts and how they were resolved

## Related

- `@.cursor/commands/pr-review.md` (previous step in PR flow)
- `@.cursor/commands/push.md` (next step in main direct flow)
- `@.cursor/rules/commit-message-format.mdc` (for squash commit messages)
