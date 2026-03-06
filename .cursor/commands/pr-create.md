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

#### Pre-flight checklist (REQUIRED before `gh pr create`)

Before running `gh pr create`, verify the body contains ALL required sections. Missing sections cause `check-policy` CI failure.

| Section | Required? | Notes |
|---------|-----------|-------|
| `## Summary` | Always | 1-3 bullet points |
| `## Traceability` | Always | `Closes #N` or Exception block |
| `## Risk / Impact` | Always | Affected area, breaking change, data impact |
| `## Rollback Plan` | Non-docs/test | How to revert; `N/A` for docs/test only |
| `## Review Checklist` | Always | Verification checkboxes |

Do NOT compose the PR body from memory. Use the template below exactly.

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

#### Exception path (hotfix / no-issue / docs-only)

This is the **required delivery method for all code changes that bypass the Issue-driven flow**, including `hotfix`. Direct push to `main` is not permitted for code changes — only `docs-only` may use `push` instead.

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
   gh run view <run_id> --log-failed
   ```
3. **Fix the root cause** — choose the right fix based on the failure type:

   | Failed job | Likely cause | Fix method |
   |------------|-------------|------------|
   | `check-policy` | PR body missing required sections | Edit PR body via `gh api repos/{owner}/{repo}/pulls/<N> -X PATCH -f body="..."` |
   | `ci-config` | YAML/Makefile syntax error | Fix in working tree, commit, push |
   | `format-check` | Unformatted R code | Run `make format`, commit, push |
   | `lint` | Lint errors | Fix code, commit, push |
   | `test` / `check` | Test failure or R CMD check error | Fix code, commit, push |
   | `validate-schemas` | Schema/code inconsistency | Fix schema or S7 class, commit, push |

   **For `check-policy` failures** (PR body issues): Update the PR body directly without a new commit:
   ```bash
   gh api repos/{owner}/{repo}/pulls/<N> -X PATCH -f body="<corrected body>"
   ```
   This triggers a `check-policy` re-run without polluting the commit history.

4. **For code fixes**: Commit the fix (follow `@.cursor/rules/commit-message-format.mdc`, use `fix(scope):` prefix, include `Refs: #<issue>`), then push:
   ```bash
   git push
   ```
5. **Return to Step 5** (monitor CI again).

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
