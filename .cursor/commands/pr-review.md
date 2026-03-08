# pr-review

## Purpose

Review a pull request: inspect the diff, verify CI status, check Issue DoD fulfillment, and produce a merge recommendation.

**This command produces a judgment only.** Merge execution is handled by `pr-merge`.

## When to use

- After `pr-create` and CI has run
- When reviewing a PR from another contributor or AI agent

## Contract

1. Read all user-attached `@...` context first (PR description, diff, requirements).
2. If required context is missing, ask for the exact `@...` files/info and stop.
3. Do NOT execute merge. Always delegate merge to `pr-merge`.
4. Do not assume other Cursor commands exist; if you mention them, they must be optional.

## Inputs (ask if missing)

- PR number or URL (required)
- Requirements/acceptance criteria (`@docs/adr/`) (recommended)

## Steps

### 1. Gather PR context

```bash
gh pr view <PR-number> --json title,body,files,commits,reviews,checks
```

### 2. Verify Issue linkage

Check that the PR body contains `Closes #<issue>` or `Fixes #<issue>`. If missing and no exception label (`no-issue`) is present, flag this as a required change.

```bash
gh pr view <PR-number> --json body --jq '.body'
```

### 3. Retrieve the linked Issue's DoD

```bash
gh issue view <issue-number>
```

Extract the acceptance criteria / Definition of Done from the Issue.

### 4. Inspect the diff

```bash
gh pr diff <PR-number>
```

### 5. Verify CI status

```bash
gh pr checks <PR-number>
```

All required checks must pass. If any check fails, the PR is not ready for merge.

### 6. Code review

| Category | What to check |
|---------|---------------|
| **Issue DoD** | all acceptance criteria from the Issue are met |
| **Change overview** | files changed, diff size |
| **Code quality** | readability, naming, duplication |
| **Spec alignment** | aligns with ADRs (`docs/adr/`) |
| **Type safety** | S7 properties have explicit types, no `class_any` |
| **Test quality** | (1) test matrix exists and matches change surface, (2) positive/negative balance acceptable, (3) boundary cases covered (0/min/max/±1/empty/NULL), (4) Given/When/Then comments present, (5) exceptions validate type+message, (6) branch coverage reasonable, (7) new params have wiring/effect tests |
| **Traceability** | `Closes #<issue>` present, `Refs: #<issue>` in commits |
| **Risk / Rollback** | risk assessment and rollback plan documented in PR |

### 7. Update PR Review Checklist

Based on the review findings, update the `## Review Checklist` in the PR body:

- **"Acceptance criteria from linked Issue are met"**: Check `[x]` if all DoD criteria from step 3 are satisfied. Leave unchecked if any criterion is not met.
- **"No untested new functionality introduced"**: Check `[x]` if the test quality review (step 6) confirms adequate coverage. Leave unchecked if new code paths lack tests.

For items left unchecked, note the reason in the merge recommendation (step 8).

```bash
gh api repos/{owner}/{repo}/pulls/<PR-number> -X PATCH -f body="<updated body>"
```

### 8. Produce merge recommendation

```text
## Merge decision

### Conclusion: Mergeable / Changes required

### Merge strategy: squash / merge
- Reason: (e.g., "AI-created PR with many micro-commits")

### Issue DoD check
- [ ] Criterion 1: met / not met
- [ ] Criterion 2: met / not met

### Reasons
- <evidence for each criterion>

### Required changes (if any)
1. Fix xxx
2. Add yyy
```

If the conclusion is "Mergeable", recommend running `pr-merge` as the next step.

If the conclusion is "Changes required", list the required changes and stop.

## Output (response format)

- **PR summary**: title, branch, files changed, diff size
- **Issue**: `#<number>` linked, DoD fulfillment status
- **CI status**: pass / fail (with details)
- **Review findings**: grouped by category
- **Merge decision**: mergeable (recommended strategy) / changes required (list)
- **Next step**: `pr-merge` (if mergeable) / fix and re-push (if changes required)

## Related

- `@.cursor/commands/pr-merge.md` (next step when mergeable)
- `@.cursor/commands/pr-create.md` (PR creation)
- `@.cursor/rules/test-strategy.mdc` (test quality criteria)
