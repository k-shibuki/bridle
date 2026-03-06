# push

## Purpose

Push `main` to `origin/main` safely. This command is for the **docs-only exception flow only**.

> **IMPORTANT**: This command is restricted to `docs-only` (documentation-only changes with no code impact). All code changes — including `hotfix` — must go through a PR via `pr-create`. Direct push of code to `main` is never permitted.

## When to use

- **docs-only**: Documentation-only changes with no code impact (README, ADR, comments, Cursor rules/commands text)

Do NOT use for: feature work, bug fixes (`fix`), hotfixes (`hotfix`), refactors, CI changes, or any code-impacting change. Use `pr-create` (exception path) for those.

## Preconditions

- You are on `main` with commits to push.
- The change is **documentation only** — no R code, no CI config, no Makefile logic changes.
- The commit message explains this is a docs-only change.

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
   - Confirm the change is `docs-only` (no code impact whatsoever)
   - Confirm the commit body explains this is a documentation-only change
   - **If the change touches any code, CI config, or Makefile logic**: STOP and use `pr-create` instead

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
- **Exception type**: docs-only
- **Justification**: why PR flow was bypassed
- **Commits pushed**: list (or "none")
- **Push result**: success / failure + error summary if failed

## Related

- `@.cursor/commands/commit.md` (previous step)
- `@.cursor/commands/pr-create.md` (standard flow — use this for all code changes including hotfix)
