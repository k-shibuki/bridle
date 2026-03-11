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
- If no Issue exists, the user must explicitly confirm this is an exception (`hotfix` or `no-issue`)

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

The `pre-push` hook automatically runs differential checks appropriate to the changed files:

- **R changes**: `format-check` + `changed-lint` + `changed-test`
- **Schema changes**: `validate-schemas`
- **renv changes**: `renv-check`
- **KB changes**: `kb-validate`

All matching change types trigger independently (no `elif` single-match). If any check fails, fix before proceeding. Do NOT push with the intent of "CI will catch it."

### 3b. Push branch to remote

```bash
git push -u origin HEAD
```

### 3c. Verify base branch (REQUIRED — `HS-PR-BASE`)

Per `@.cursor/rules/agent-safety.mdc` `HS-PR-BASE`: always use `main` as the PR base branch. Do not use `--base feat/<branch>`.

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

#### Pre-flight: required sections

Before running `gh pr create`, verify the body contains ALL required sections. Missing sections cause `check-policy` CI failure.

| Section | Required? | Notes |
|---------|-----------|-------|
| `## Summary` | Always | 1-3 bullet points |
| `## Traceability` | Always | `Closes #N` or Exception block |
| `## Risk / Impact` | Always | Affected area, breaking change, data impact |
| `## Rollback Plan` | Non-docs/test | How to revert; `N/A` for docs/test only |

#### PR body template (SSOT)

Read `@.github/PULL_REQUEST_TEMPLATE.md` and use it as the PR body. Do NOT compose the body from memory or duplicate the template here.

**Checkbox rules**:
- **Test Evidence** is a free-text section for CI result audit trail — no checkboxes.
- **Schema Impact** checkboxes are a selection (not a gate) — check the applicable one at creation.

#### Standard path (Issue exists)

The PR body **must** include `Closes #<issue>` for automatic Issue closure on merge. Delete the `## Exception` section from the template.

```bash
gh pr create --title "<type>(<scope>): <description>" \
  --label "<type>" \
  --body "<body from PULL_REQUEST_TEMPLATE.md with placeholders filled>"
```

#### Exception path (hotfix / no-issue)

This is the **required delivery method for all code changes that bypass the Issue-driven flow**, including `hotfix`. Direct push to `main` is not permitted for code changes — only documentation-only changes (type: `docs` + exception: `no-issue`) may use direct push via `commit` (docs-only path).

When the user explicitly confirms an exception, add a label and fill the `## Exception` section instead of `Closes #`.

```bash
gh pr create --title "<type>(<scope>): <description>" \
  --label "<type>" \
  --label "<no-issue|hotfix>" \
  --body "<body from PULL_REQUEST_TEMPLATE.md with Exception section filled>"
```

### 5. Bot review and CI monitoring

Per `subagent-policy.mdc`: blocking operations (CI polling, bot review wait) MUST be delegated to a background subagent. The main agent must not poll inline with `sleep` loops.

#### 5a. CodeRabbit (agent-triggered — always)

Agent triggers CodeRabbit on every PR immediately after creation:

```bash
gh pr comment <PR> --body "@coderabbitai review"
```

Auto-review is OFF (requires paid seat). The agent MUST trigger explicitly.

#### 5b. Codex (user instruction only)

Codex is triggered **only when the user explicitly instructs**. The agent
never triggers Codex autonomously. If the user requests Codex review:

```bash
gh pr comment <PR> --body "@codex review"
```

#### 5b′. Capture trigger metadata and delegate

After triggering, capture each reviewer's comment ID and `created_at` timestamp:

```bash
gh api repos/{owner}/{repo}/issues/<PR>/comments \
  --jq '[.[] | select(.user.login == "{agent_login}") | select(.body | test("@coderabbitai review"))] | last | {id: .id, created_at: .created_at}'
```

Then delegate CI + review monitoring to a background subagent using `.cursor/templates/delegation--review-wait.md` (Monitor CI: YES). Pass `trigger_id` and `trigger_time` for each triggered reviewer. See `@.cursor/knowledge/agent--delegation-decision.md` for the decision flowchart.

**Auto-merge guard**: MUST NOT set auto-merge until bot review completes — see `@.cursor/commands/pr-merge.md` § Auto-merge for preconditions.

### 6. If CI fails: diagnose, fix, re-push

Per `@.cursor/rules/coding-policy.mdc` § CI Failure Autonomy, the agent must autonomously diagnose and fix CI failures before escalating. See `@.cursor/knowledge/ci--failure-triage.md` for classification (code defect / format drift / infrastructure / policy / flaky) and diagnostic commands.

**For `check-policy` failures** (PR body issues): Update the PR body directly without a new commit:
```bash
gh api repos/{owner}/{repo}/pulls/<N> -X PATCH -f body="<corrected body>"
```

For code fixes: commit the fix (follow `@.cursor/rules/commit-format.mdc`, `fix(scope):` prefix, `Refs: #<issue>`), push, and return to Step 5.

Escalate only after: (a) diagnosis, (b) fix attempt, (c) fix did not resolve.

### 7. Report status

After CI passes, report the PR status. Merge is handled by `pr-review` + `pr-merge`.

If the repository requires a review before merge (branch protection), report the CI-green status and stop.

## Output (response format)

- **Issue**: `#<number>` being closed by this PR
- **Branch**: name
- **Commits**: list of commits on the branch
- **PR URL**: link to the created PR
- **Bot review**: CodeRabbit: triggered (comment URL) / Codex: triggered (comment URL) | skipped (reason)
- **CI result**: all pass / failure details and actions taken

## Related

- `@.cursor/rules/commit-format.mdc` (commit + branch naming convention)
- `@.cursor/commands/pr-review.md` (next step: review)
- `@.cursor/commands/pr-merge.md` (merge strategy reference)
