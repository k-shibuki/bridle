# pr-create

## Purpose

Create a feature branch (if needed), commit, push, and open a pull request on GitHub that closes the tracking Issue.

## When to use

- After `quality-check` / `test-regression` pass, when the change is ready for CI validation and review

## Preconditions

- `gh` CLI is authenticated (`gh auth status`)
- Changes are either already committed, or staged/unstaged and ready to commit
- A tracking Issue exists for this change (see Exception path below if not)

## Inputs (ask if missing)

- **Issue number** (required unless exception): the GitHub Issue this PR closes (e.g., `#42`)
- If no Issue exists, the user must explicitly confirm this is an exception (`hotfix`, `docs-only`, or `no-issue`)

## Steps

### 1. Ensure you are on a feature branch

If on `main`, create a feature branch per `@.cursor/rules/commit-format.mdc` § Branch Naming Convention.

```bash
current_branch=$(git branch --show-current)

if [ "$current_branch" = "main" ]; then
    echo "On main -- creating feature branch."
    git checkout -b <prefix>/<issue-number>-<short-description>
fi
```

### 2. Commit changes (if uncommitted)

If there are uncommitted changes, commit them following `@.cursor/rules/commit-format.mdc`. Include `Refs: #<issue>` in the footer.

```bash
git status --short
```

### 3. Local verification gate (REQUIRED before push)

Run the following locally and confirm zero issues before pushing:

```bash
make ci-fast        # validate-schemas + lint
make format-check   # styler dry-run
```

If either fails, fix before proceeding. Do NOT push with the intent of "CI will catch it."

### 3b. Push branch to remote

```bash
git push -u origin HEAD
```

### 3c. Verify base branch (REQUIRED)

**Always use `main` as the PR base branch.** Do not use `--base feat/<branch>`.

| Situation | Base | Rationale |
|---|---|---|
| Independent PR | `main` | Standard |
| Dependent PR (dep not yet merged) | `main` | Feature-base PRs auto-close when base is deleted on merge |

When developing on a branch that depends on unmerged work:
1. Develop locally by merging/rebasing the dependency branch
2. Before `git push`, rebase onto `origin/main`
3. Create the PR with `--base main` (default)
4. Document the dependency in the PR body under "Related ADR / Issue"

The dependency's code may be missing on `main` during CI. This is acceptable —
the PR will be merged **after** the dependency PR, at which point CI re-runs on
a main that already contains the prerequisite code.

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
gh pr create --title "<type>(<scope>): <description>" \
  --label "<type>" \
  --body "$(cat <<'EOF'
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

This is the **required delivery method for all code changes that bypass the Issue-driven flow**, including `hotfix`. Direct push to `main` is not permitted for code changes — only `docs-only` may use direct push via `commit` (docs-only path).

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

Per `agent-safety.mdc` Hard Stop #7: CI polling MUST be delegated to a background subagent. The main agent must not poll CI inline with `sleep` loops.

**Delegation**: Use `@.cursor/rules/subagent-policy.mdc` delegation pattern with prompt templates from `@.cursor/knowledge/agent--delegation-templates.md` (Template 1: CI-Wait + Merge, or Template 3: CI-Wait Only).

**Polling strategy**: The subagent follows the Adaptive Polling Strategy defined in `@.cursor/knowledge/ci--job-dependency-graph.md` § Adaptive Polling Strategy (the SSOT for polling intervals and time budgets).

```bash
# Quick initial check (before delegating to subagent)
gh pr checks <PR_NUMBER>
```

### 6. If CI fails: diagnose, fix, re-push

**The agent must autonomously diagnose and fix CI failures.** Do not merely report failures to the user — investigate the root cause, fix it, and re-push. Escalate to the user only after a genuine fix attempt has failed.

1. **Identify the failed job(s)** from `gh pr checks` output.
2. **Fetch failure logs**:
   ```bash
   gh run view <run_id> --log-failed
   ```
3. **Classify the failure** — infrastructure vs code:

   **Infrastructure failures** (setup steps, package downloads, network timeouts):
   - Read the full error context (not just the error line — check 10+ lines around it).
   - Identify the root cause: missing env var, wrong config, transient network issue, etc.
   - **If fixable** (e.g., missing `RENV_CONFIG_AUTOLOADER_ENABLED`, wrong CI config): fix the workflow/config file, commit, push. One retry with `gh run rerun <RUN_ID> --failed` is allowed only for genuinely transient issues (e.g., CDN outage) that cannot be fixed by code changes.
   - **If the same infrastructure failure recurs**: it is NOT transient — investigate deeper (compare with passing jobs, check env vars, check config differences).

   **Code failures** — choose the right fix:

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

4. **For code fixes**: Commit the fix (follow `@.cursor/rules/commit-format.mdc`, use `fix(scope):` prefix, include `Refs: #<issue>`), then push:
   ```bash
   git push
   ```
5. **Return to Step 5** (monitor CI again).

Escalate to the user only when: (a) you have diagnosed the root cause, (b) attempted a fix, and (c) the fix did not resolve the issue. Include the diagnosis, what you tried, and why it didn't work.

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

- `@.cursor/rules/commit-format.mdc` (commit + branch naming convention)
- `@.cursor/commands/pr-review.md` (next step: review)
- `@.cursor/commands/pr-merge.md` (merge strategy reference)
