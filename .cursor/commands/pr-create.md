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

### 5. Verify CI started

```bash
gh pr checks
```

## Output (response format)

- **Branch**: name
- **Commits**: list of commits on the branch
- **PR URL**: link to the created PR
- **CI status**: pending / running

## Related

- `@.cursor/rules/commit-message-format.mdc` (commit + branch naming convention)
- `@.cursor/commands/pr-review.md` (next step: review the PR)
- `@.cursor/commands/merge.md` (final step: merge the PR)
