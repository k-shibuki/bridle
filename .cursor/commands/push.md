# push

## Purpose

Push `main` to `origin/main` safely. This command is for the **exception flow only**.

> **IMPORTANT**: This command is restricted to `hotfix` (critical production fixes) and `docs-only` (documentation-only changes with no code impact). For all normal changes, use `pr-create` to push a feature branch and open a PR instead.

## When to use

- **hotfix**: Critical production fix that cannot wait for the full PR flow
- **docs-only**: Documentation-only changes with no code impact (README, ADR, comments)

Do NOT use for: feature work, bug fixes, refactors, CI changes, or any code-impacting change.

## Preconditions

- You are on `main` with commits to push.
- Quality checks and tests have passed (via `quality-check` + `regression-test`, or `ci`).
- The commit message justifies the exception (e.g., "Hotfix: critical regression in production").

## Steps

1. Confirm you are on `main` and there are commits to push:

```bash
current_branch=$(git branch --show-current)
echo "Current branch: $current_branch"

if [ "$current_branch" != "main" ]; then
    echo "ERROR: Not on main. For feature branches, use pr-create instead."
    exit 1
fi

echo "=== Commits to push ==="
git log origin/main..main --oneline

if [ -z "$(git log origin/main..main --oneline)" ]; then
    echo "No commits to push"
    exit 0
fi
```

2. Verify the exception is justified:
   - Confirm the change is either `hotfix` or `docs-only`
   - Confirm the commit body explains why the PR flow was bypassed

3. Push:

```bash
git push origin main
```

4. Verify:

```bash
git log origin/main..main --oneline
```

## Output (response format)

- **Branch**: current branch
- **Exception type**: hotfix / docs-only
- **Justification**: why PR flow was bypassed
- **Commits pushed**: list (or "none")
- **Push result**: success / failure + error summary if failed

## Related

- `@.cursor/commands/commit.md` (previous step)
- `@.cursor/commands/pr-create.md` (standard flow — use this for normal changes)
