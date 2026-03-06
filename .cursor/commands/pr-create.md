# pr-create

## Purpose

Create a feature branch (if needed), commit, push, and open a pull request on GitHub.

## When to use

- After `quality-check` / `regression-test` pass, when the change warrants a PR
- When CI validation via GitHub Actions is desired before merging

## Preconditions

- `gh` CLI is authenticated (`gh auth status`)
- Changes are either already committed, or staged/unstaged and ready to commit

## Steps

### 1. Ensure you are on a feature branch

If on `main`, create a feature branch first. Branch names follow the convention in `@.cursor/rules/commit-message-format.mdc`.

```bash
current_branch=$(git branch --show-current)

if [ "$current_branch" = "main" ]; then
    echo "On main -- creating feature branch."
    # Branch name: <type>/<short-description>
    git checkout -b <type>/<short-description>
fi
```

### 2. Commit changes (if uncommitted)

If there are uncommitted changes, commit them following `@.cursor/rules/commit-message-format.mdc`.

```bash
git status --short
# If changes exist, commit (follow /commit procedure)
```

### 3. Push branch to remote

```bash
git push -u origin HEAD
```

### 4. Create PR

```bash
gh pr create --fill
```

If the auto-filled title/body is insufficient, use the PR template:

```bash
gh pr create --title "<type>: <description>" --body "$(cat <<'EOF'
## Summary

- <change summary>

## Related ADR / Issue

- ADR: <if applicable>
- Issue: <if applicable>

EOF
)"
```

### 5. Monitor CI until completion

Poll CI checks until all jobs reach a terminal state (pass / fail / skipping).

```bash
gh pr checks --watch
```

If `--watch` is unavailable or times out, poll manually:

```bash
gh pr checks          # repeat until no "pending" remains
```

### 6. If CI fails: diagnose → fix → re-push

Repeat until CI passes or the issue requires user intervention.

1. **Identify the failed job(s)** from `gh pr checks` output.
2. **Fetch failure logs**:
   ```bash
   gh run view <run_id> --job <job_id> --log-failed
   ```
3. **Fix the root cause** in the local working tree.
4. **Commit the fix** (follow `@.cursor/rules/commit-message-format.mdc`, use `fix(scope):` prefix).
5. **Push**:
   ```bash
   git push
   ```
6. **Return to Step 5** (monitor CI again).

If a failure is clearly outside your control (e.g. infrastructure flake, third-party service outage), report it to the user rather than retrying indefinitely.

### 7. Merge the PR

After CI passes, merge using the appropriate strategy (see `@.cursor/commands/pr-merge.md` for strategy selection).

AI-created PRs typically use **squash** to consolidate micro-commits.

```bash
gh pr merge <PR-number> --squash --delete-branch
```

Then update local main:

```bash
git checkout main
git pull origin main
```

If the repository requires a review before merge (branch protection), report the CI-green status and stop. The user or another agent can then run `pr-review` to complete the process.

## Output (response format)

- **Branch**: name
- **Commits**: list of commits on the branch
- **PR URL**: link to the created PR
- **CI result**: all pass / failure details and actions taken
- **Merge result**: merged (strategy) / blocked (reason)

## Related

- `@.cursor/rules/commit-message-format.mdc` (commit + branch naming convention)
- `@.cursor/commands/pr-merge.md` (merge strategy reference)
- `@.cursor/commands/pr-review.md` (for PRs that require review before merge)
