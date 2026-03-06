# push

## Purpose

Push `main` to `origin/main` safely. This command is for the **main direct flow only**.

For the PR flow, use `pr-create` to push a feature branch instead.

## When to use

- After `commit` (main direct flow for small changes)
- After local `merge` when main has new commits

## Preconditions

- You are on `main` with commits to push.
- Quality checks and tests have passed (via `quality-check` + `regression-test`, or `ci`).

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

2. Push:

```bash
git push origin main
```

3. Verify:

```bash
git log origin/main..main --oneline
```

## Output (response format)

- **Branch**: current branch
- **Commits pushed**: list (or "none")
- **Push result**: success / failure + error summary if failed

## Related

- `@.cursor/commands/commit.md` (previous step)
- `@.cursor/commands/pr-create.md` (alternative: PR flow)
