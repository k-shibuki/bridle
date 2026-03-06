# pr-review

## Purpose

Review a pull request: inspect the diff, verify CI status, and produce a merge recommendation.
Merge execution is delegated to `merge`.

## When to use

- After `pr-create` and CI has run
- When reviewing a PR from another contributor or AI agent

## Contract

1. Read all user-attached `@...` context first (PR description, diff, requirements).
2. If required context is missing, ask for the exact `@...` files/info and stop.
3. If the review conclusion is "Mergeable", execute the merge (Step 6).
4. Do not assume other Cursor commands exist; if you mention them, they must be optional.

## Inputs (ask if missing)

- PR number or URL (required)
- Requirements/acceptance criteria (`@docs/adr/`) (recommended)

## Steps

### 1. Gather PR context

```bash
gh pr view <PR-number> --json title,body,files,commits,reviews,checks
```

### 2. Inspect the diff

```bash
gh pr diff <PR-number>
```

### 3. Verify CI status

```bash
gh pr checks <PR-number>
```

All required checks must pass. If any check fails, the PR is not ready for merge.

### 4. Code review

| Category | What to check |
|---------|---------------|
| **Change overview** | files changed, diff size |
| **Code quality** | readability, naming, duplication |
| **Spec alignment** | aligns with ADRs (`docs/adr/`) |
| **Type safety** | S7 properties have explicit types, no `class_any` |
| **Tests** | tests exist, negative cases covered |

### 5. Produce merge recommendation

```text
## Merge decision

### Conclusion: Mergeable / Changes required

### Merge strategy: squash / merge
- Reason: (e.g., "Cloud agent branch with many micro-commits")

### Reasons
- <evidence for each criterion>

### Required changes (if any)
1. Fix xxx
2. Add yyy
```

### 6. Execute merge (if Mergeable)

If the review conclusion is "Mergeable" and CI is green, merge the PR using the recommended strategy (see `@.cursor/commands/pr-merge.md` for strategy selection).

```bash
# Squash (default for AI-created PRs with many commits)
gh pr merge <PR-number> --squash --delete-branch

# or normal merge (for well-organized human commits)
gh pr merge <PR-number> --merge --delete-branch
```

Then update local main:

```bash
git checkout main
git pull origin main
```

If the conclusion is "Changes required", list the required changes and stop. Do not merge.

## Output (response format)

- **PR summary**: title, branch, files changed, diff size
- **CI status**: pass / fail (with details)
- **Review findings**: grouped by category
- **Merge decision**: mergeable (strategy, result) / changes required (list)

## Related

- `@.cursor/commands/pr-merge.md` (merge strategy reference)
- `@.cursor/commands/pr-create.md` (PR creation)
- `@.cursor/rules/test-strategy.mdc`
- `@.cursor/rules/commit-message-format.mdc`
