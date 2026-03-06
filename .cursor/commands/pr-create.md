# pr-create

## Purpose

Create a feature branch (if needed), commit, push, and open a pull request on GitHub that closes the tracking Issue.

## When to use

- After `quality-check` / `regression-test` pass, when the change is ready for CI validation and review

## Preconditions

- `gh` CLI is authenticated (`gh auth status`)
- Changes are either already committed, or staged/unstaged and ready to commit
- A tracking Issue exists for this change (see Exception path below if not)

## Inputs (ask if missing)

- **Issue number** (required unless exception): the GitHub Issue this PR closes (e.g., `#42`)
- If no Issue exists, the user must explicitly confirm this is an exception (`hotfix`, `docs-only`, or `no-issue`)

## Steps

### 1. Ensure you are on a feature branch

If on `main`, create a feature branch. Branch names follow the convention: `<prefix>/<issue-number>-<short-description>`.

```bash
current_branch=$(git branch --show-current)

if [ "$current_branch" = "main" ]; then
    echo "On main -- creating feature branch."
    git checkout -b <prefix>/<issue-number>-<short-description>
fi
```

### 2. Commit changes (if uncommitted)

If there are uncommitted changes, commit them following `@.cursor/rules/commit-message-format.mdc`. Include `Refs: #<issue>` in the footer.

```bash
git status --short
```

### 3. Push branch to remote

```bash
git push -u origin HEAD
```

### 4. Create PR

#### Standard path (Issue exists)

The PR body **must** include `Closes #<issue>` for automatic Issue closure on merge. Delete the `## Exception` section.

```bash
gh pr create --title "<type>(<scope>): <description>" --body "$(cat <<'EOF'
## Summary

- <change summary>

## Traceability

Closes #<issue-number>

## Related ADR / Issue

- ADR: <if applicable>

## Schema Impact

- [ ] No schema impact
- [ ] Schema updated
- [ ] S7 class updated
- [ ] Both updated (consistency verified)

## Test Evidence

- [ ] `make test` passes
- [ ] `make check` passes
- [ ] New tests added for new functionality

## Risk / Impact

- Affected area: <what is affected>
- Breaking change: no
- Data impact: none

## Rollback Plan

<how to revert>

## Review Checklist

- [ ] Code follows project conventions
- [ ] No prohibited patterns
- [ ] ADR compliance verified
- [ ] Issue DoD criteria met

EOF
)"
```

#### Exception path (no Issue)

When the user explicitly confirms an exception, add a label and fill the `## Exception` section instead of `Closes #`.

```bash
gh pr create --title "<type>(<scope>): <description>" \
  --label "<no-issue|hotfix|docs-only>" \
  --body "$(cat <<'EOF'
## Summary

- <change summary>

## Traceability

<!-- No Issue for this exception PR -->

## Exception

- Type: <no-issue / hotfix / docs-only>
- Justification: <why this PR bypasses the Issue-driven flow>

## Related ADR / Issue

- ADR: <if applicable>

## Schema Impact

- [ ] No schema impact

## Test Evidence

- [ ] `make test` passes
- [ ] `make check` passes

## Risk / Impact

- Affected area: <what is affected>
- Breaking change: no
- Data impact: none

## Rollback Plan

<how to revert>

## Review Checklist

- [ ] Code follows project conventions
- [ ] No prohibited patterns
- [ ] ADR compliance verified

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
gh pr checks
```

### 6. If CI fails: diagnose, fix, re-push

Repeat until CI passes or the issue requires user intervention.

1. **Identify the failed job(s)** from `gh pr checks` output.
2. **Fetch failure logs**:
   ```bash
   gh run view <run_id> --job <job_id> --log-failed
   ```
3. **Fix the root cause** in the local working tree.
4. **Commit the fix** (follow `@.cursor/rules/commit-message-format.mdc`, use `fix(scope):` prefix, include `Refs: #<issue>`).
5. **Push**:
   ```bash
   git push
   ```
6. **Return to Step 5** (monitor CI again).

If a failure is clearly outside your control (e.g. infrastructure flake, third-party service outage), report it to the user rather than retrying indefinitely.

### 7. Report status

After CI passes, report the PR status. Merge is handled by `pr-review` + `pr-merge`.

If the repository requires a review before merge (branch protection), report the CI-green status and stop.

## Output (response format)

- **Issue**: `#<number>` being closed by this PR
- **Branch**: name
- **Commits**: list of commits on the branch
- **PR URL**: link to the created PR
- **CI result**: all pass / failure details and actions taken

## Related

- `@.cursor/rules/commit-message-format.mdc` (commit + branch naming convention)
- `@.cursor/commands/pr-review.md` (next step: review)
- `@.cursor/commands/pr-merge.md` (merge strategy reference)
