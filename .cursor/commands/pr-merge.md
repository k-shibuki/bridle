# pr-merge

## Purpose

Execute a merge after `pr-review` concludes "Mergeable" or the user explicitly instructs.

## Inputs

- PR number (required)
- Merge strategy: squash / merge (required)

## Sense

Run `make evidence-pull-request PR=<N>` for structured PR state.

Key fields to extract:
- `ci.status` — must be `"success"`
- `merge.merge_state_status` — must be `CLEAN`, `HAS_HOOKS`, `BEHIND`, or `UNSTABLE`
- `reviews.threads_unresolved` — must be 0
- `reviews.disposition` — must be `"approved"` or user explicit merge
- `reviews.bot_coderabbit.review_submitted_at` vs `reviews.last_push_at` — freshness

## Orient

### Merge preconditions

Consult `controls--merge-invariants.md` for the 5 mandatory preconditions. All must be TRUE:

1. CI is green (`HS-CI-MERGE`)
2. Review concluded mergeable
3. CI evidence recorded (`## Test Evidence` non-empty)
4. Branch is mergeable (merge state resolution table in Knowledge atom)
5. Bot review covers latest push (freshness check)

### Merge strategy selection

| Source | Pattern | Strategy |
|--------|---------|----------|
| AI agent | Many micro-commits | **squash** |
| Human | 2-5 meaningful commits | merge |

### High-risk change policy

Changes to schemas, CI pipeline, AI rules, or security areas require extra caution. Confirm with user before merging.

### FSM context

This command runs in state **ReviewDone**. Valid transitions: → CycleComplete (merge success) or → CIFailed (post-merge CI failure on main).

## Act

### 1. Verify preconditions

Check each precondition from `controls--merge-invariants.md` against evidence fields. If any fails, **STOP** and report the blocking condition.

### 2. Record CI evidence

If `## Test Evidence` is empty, update PR body with CI summary:

```bash
gh pr edit <N> --body "<updated body with CI evidence>"
```

### 3. Merge

**Preferred: auto-merge** (Deterministic enforcement):

```bash
gh pr merge <N> --auto --squash
```

Preconditions for auto-merge per `controls--merge-invariants.md` § Auto-Merge Decision:
- All mandatory preconditions pass
- Consensus on all threads (unresolved == 0)
- Bot review NOT pending

**Fallback: delegated merge** when auto-merge fails:
- Use `.cursor/templates/delegation--ci-wait-only.md`
- Main agent executes `gh pr merge <N> --squash` after subagent reports CI green

**NEVER use `--admin` flag** (`HS-CI-MERGE(a)`).

### 4. Post-merge cleanup

```bash
git checkout main
git pull origin main
git fetch --prune origin
```

Delete local feature branch (force-delete after squash merge):

```bash
pr_state=$(gh pr list --head <branch> --state merged --json number -q '.[0].number')
[ -n "$pr_state" ] && git branch -D <branch> 2>/dev/null || true
```

### 5. Local merge (documentation-only exception)

For docs-only changes (type: `docs` + exception: `no-issue`) that bypass PR flow:

```bash
git checkout main && git merge --no-edit <branch>
```

**Code changes (including hotfix) MUST use the GitHub PR merge flow above.**

## Guard / Validation

- `HS-CI-MERGE`: CI must be green; `--admin` prohibited; amend+force-push prohibited
- `HS-CI-MERGE` auto-merge guard: MUST NOT set auto-merge while bot review is pending
- `required_conversation_resolution`: all threads resolved before merge
- Post-merge: `R-CMD-check.yaml` runs on main push (safety net)

> **Observation gap**: All external state is acquired via `make` evidence targets. If information is not available from any target, report it as a missing evidence target.

> **Anti-pattern — judgment creep**: Merge preconditions are declared in `controls--merge-invariants.md`. This procedure checks them — it does not redefine them.

## Related

- `controls--merge-invariants.md` — preconditions, merge state resolution, auto-merge decision
- `pr-review.md` — produces the merge recommendation
- `agent-safety.mdc` § HS-CI-MERGE — Hard Stop definition
- `git--squash-merge-dependent-branch.md` — dependent chain rebase
