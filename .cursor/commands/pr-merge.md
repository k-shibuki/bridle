# pr-merge

## Purpose

Execute a merge — either via GitHub (for PR flow) or locally (for exception flow).

## When to use

- After `pr-review` concludes "Mergeable" (standard PR flow, including hotfix exception PRs)
- After `commit` and successful quality/tests (documentation-only exception flow on local branch)

## Mandatory Preconditions (verify before ANY merge)

These checks are the first step of `pr-merge` and cannot be skipped:

1. **CI must be green**:
   ```bash
   gh pr checks <PR-number>
   ```
   If any check is not `pass`, **STOP**. Do not merge. Fix the failure or wait for completion.

2. **One of the following must be true**:
   - `pr-review` concluded "Mergeable"
   - User explicitly instructed to merge

If either precondition is not met, do not proceed to merge. Report the blocking condition instead.

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

After merge, sync local tracking information:

```bash
git checkout main
git pull origin main
git fetch --prune origin
```

`--prune` removes local remote-tracking references (e.g. `origin/feat/...`) for branches that have been deleted on the remote (typically by `--delete-branch` above).

### Clean up local feature branch

If the local feature branch still exists after the GitHub merge, delete it:

```bash
git branch -d <branch-name> 2>/dev/null || true
```

**Squash merge caveat**: After a squash merge, `git branch -d` may fail with "not fully merged" because git does not recognize the squashed commit as an ancestor. Use force-delete only after confirming the PR is merged:

```bash
pr_state=$(gh pr list --head <branch-name> --state merged --json number -q '.[0].number')
if [ -n "$pr_state" ]; then
  git branch -D <branch-name> 2>/dev/null || true
fi
```

See `@.cursor/knowledge/git--squash-merge-dependent-branch.md` for related patterns.

## Local merge (documentation-only exception flow)

For documentation-only changes (type: `docs` + exception: `no-issue`) that bypassed the PR flow. **`hotfix` changes must use the GitHub PR merge flow above** — direct push / local merge is not permitted for code changes.

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

After `--squash`, you must run `git commit` with a message following `commit-format.mdc`.

## Delegated merge (background subagent)

CI polling is always delegated to a background subagent (Hard Stop #7). This frees the main agent for productive work — whether implementing the next Issue or performing housekeeping.

### When to use

- CI is still running on a PR (always — inline polling is prohibited)
- Multiple PRs need sequential merge (rebase → CI → merge chain)
- Dependent PRs with shared commit history need `--onto` rebase after squash merge

### How to delegate

Launch a `shell` subagent with `model: "fast"` and `run_in_background: true`.

Choose the appropriate template from `@.cursor/knowledge/agent--delegation-templates.md`:

| Scenario | Template |
|----------|----------|
| Single PR, CI pending | "CI-Wait + Merge" |
| Multiple independent PRs | "Sequential PR Merge Chain" |
| PRs with shared commits (branched from each other) | "Dependent PR Merge Chain" (includes `--onto` rebase) |
| CI monitoring only (no merge) | "CI-Wait Only" |

### Completion detection

The main agent checks the subagent transcript at the next `next` re-assessment cycle. See `subagent-policy.mdc` "Completion guarantee" for the protocol.

## Constraints

- Use non-interactive git flags (`--no-edit`, `--no-pager`) to avoid hangs
- Per `@.cursor/rules/agent-safety.mdc` Hard Stop #1: CI must be green before merge
- Merge is permitted when `pr-review` concluded "Mergeable" or the user explicitly instructs to merge

## Output (response format)

- **Method**: GitHub PR merge / local merge
- **Strategy**: squash / merge
- **Result**: success / conflicts
- **Commit(s)**: resulting commit hash(es)
- **Issue**: `#<number>` closed by this merge (if applicable)
- **Notes**: any conflicts and how they were resolved

## Related

- `@.cursor/commands/pr-review.md` (previous step in PR flow)
- `@.cursor/commands/commit.md` (exception: documentation-only direct push)
- `@.cursor/rules/commit-format.mdc` (for squash commit messages)
