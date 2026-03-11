# pr-merge

## Purpose

Execute a merge — either via GitHub (for PR flow) or locally (for exception flow).

## When to use

- After `pr-review` concludes "Mergeable" (standard PR flow, including hotfix exception PRs)
- After `commit` and successful quality/tests (documentation-only exception flow on local branch)

## Mandatory Preconditions (verify before ANY merge)

These checks are the first step of `pr-merge` and cannot be skipped:

1. **CI must be green** (per `@.cursor/rules/agent-safety.mdc` `HS-CI-MERGE`):
   ```bash
   gh pr checks <PR-number>
   ```
   If any check is not `pass`, **STOP**. Do not merge. Fix the failure or wait for completion.

2. **One of the following must be true**:
   - `pr-review` concluded "Mergeable"
   - User explicitly instructed to merge

3. **Record CI evidence** (audit trail):
   If `## Test Evidence` is empty, paste a CI summary (e.g., `gh pr checks` output or "CI all pass — R jobs skipped, no R changes"). This is a record, not a gate — CI green is already enforced by precondition 1.

   ```bash
   gh api repos/{owner}/{repo}/pulls/<PR-number> -X PATCH -f body="<updated body>"
   ```

4. **Branch must be mergeable** (merge state check):

   ```bash
   gh pr view <PR-number> --json mergeStateStatus -q '.mergeStateStatus'
   ```

   | Value | Meaning | Action |
   |-------|---------|--------|
   | `CLEAN` | All checks pass, no conflicts | Merge |
   | `HAS_HOOKS` | Mergeable, pre-receive hooks will run | Merge |
   | `BEHIND` | Branch is behind main (no conflict) | Merge (allowed by `strict: false`) |
   | `UNSTABLE` | Some non-required checks failed | Merge if required checks pass |
   | `DIRTY` | Merge conflict exists | Resolve conflict, push, wait for CI |
   | `BLOCKED` | Required checks failed or reviews missing | Investigate; do not force-merge |
   | `UNKNOWN` | GitHub is computing merge status | Wait and re-query |

   With `strict: false`, `BEHIND` does not block the merge. GitHub allows merging
   as long as required checks have passed and there are no conflicts.

   **Design note**: Solo + sequential agent model has near-zero risk of conflicting
   PRs. Post-merge CI (`R-CMD-check.yaml` on push to main) acts as safety net.
   If the project moves to parallel multi-agent development, reconsider enabling
   `strict: true` or GitHub Merge Queue.

If any precondition (1-4) is not met, do not proceed to merge. Report the blocking condition and the required action.

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
gh pr merge <PR-number> --squash

# Normal merge (preserves history)
gh pr merge <PR-number> --merge
```

Remote branches are automatically deleted after merge (`delete_branch_on_merge` is
enabled in repository settings). No `--delete-branch` flag needed.

After merge, sync local tracking information:

```bash
git checkout main
git pull origin main
git fetch --prune origin
```

`--prune` removes local remote-tracking references (e.g. `origin/feat/...`) for
branches deleted by the automatic branch cleanup.

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

## Auto-merge (preferred for single PRs)

Use auto-merge to let GitHub merge automatically when all required checks pass.

**Preconditions** (all must be true):

- `pr-review` has concluded "Mergeable" on the **current** HEAD commit
- No unresolved review findings from any reviewer (CodeRabbit, Codex)
- No re-review is pending (i.e., no review-fix push since the last completed review)

If a re-review is in progress (review-fix was pushed, reviewer has not yet
responded), use the delegated merge pattern (§ below) or wait for the
re-review to complete before setting auto-merge.

```bash
gh pr merge <PR-number> --auto --squash
```

This moves the "merge after CI" operation from Steering (agent polls and merges)
to Deterministic (GitHub enforces required checks and merges automatically).

After setting auto-merge, the agent can immediately proceed to the next task.
If CI fails, GitHub cancels auto-merge automatically.

**Verify auto-merge was set** (optional):

```bash
gh pr view <PR-number> --json autoMergeRequest -q '.autoMergeRequest'
```

**Fallback**: If `gh pr merge --auto` fails (e.g., token scope issue), fall back
to the delegated merge pattern below.

## Delegated merge (background subagent)

Delegation is the **fallback** when auto-merge is not available. See
`@.cursor/knowledge/agent--delegation-templates.md` § Decision Flowchart for the
full decision tree (auto-merge → fallback → delegation).

### When to use

- `gh pr merge --auto` failed (e.g., token scope issue, API error)
- Dependent PRs with shared commit history need `--onto` rebase after squash merge
- CI monitoring without merge intent (pre-review)

### How to delegate

Launch a `shell` subagent with `model: "fast"` and `run_in_background: true`.

Choose the appropriate template from `@.cursor/knowledge/agent--delegation-templates.md`:

| Scenario | Template |
|----------|----------|
| Single PR, auto-merge failed, pr-review done | Template 1: "CI-Wait + Merge (Fallback)" |
| CI monitoring only (no merge intent) | Template 2: "CI-Wait Only" |
| PRs with shared commits (branched from each other) | Template 3: "Dependent PR Merge Chain" (includes `--onto` rebase) |

Scenarios **not listed** (single PR with pr-review done, multiple independent PRs)
are handled by auto-merge — see § Auto-merge and § Batch Auto-Merge in
`agent--delegation-templates.md`.

### Completion detection

The main agent checks the subagent transcript at the next `next` re-assessment cycle. See `subagent-policy.mdc` "Completion guarantee" for the protocol.

### Post-delegation push verification

When a subagent performed a force-push (Template 3 `--onto` rebase), verify the push reached the remote before proceeding with further branch operations:

```bash
git fetch origin
git ls-remote origin <branch> | head -1
```

Compare the remote SHA with the expected value from the subagent's return. If they differ, see `@.cursor/knowledge/git--quick-recovery.md` § Force-with-Lease Rejected. See also `@.cursor/knowledge/git--safety-checklist.md` for the full post-subagent verification checklist.

## Constraints

- Use non-interactive git flags (`--no-edit`, `--no-pager`) to avoid hangs
- Per `@.cursor/rules/agent-safety.mdc` `HS-CI-MERGE`: CI must be green before merge
- Merge is permitted when `pr-review` concluded "Mergeable" or the user explicitly instructs to merge
- Per `@.cursor/rules/agent-safety.mdc` `HS-CI-MERGE`: NEVER use `--admin` flag on `gh pr merge`, NEVER use amend+force-push in normal PR flow. See the Hard Stop definition for rationale and enforcement details.

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
