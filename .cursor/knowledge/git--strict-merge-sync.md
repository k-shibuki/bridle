---
trigger: strict merge, BEHIND, mergeStateStatus, branch not up to date, merge blocked, branch sync
---
# Strict Merge Sync (`strict: true` Branch Protection)

## What `strict: true` Does

When `required_status_checks.strict` is `true` in GitHub Branch Protection, a PR
branch **must be up to date with the base branch** (main) before merging. If main
has advanced since the PR branch was last rebased/merged, GitHub blocks the merge
with status `BEHIND`.

This prevents merging code that passed CI on a stale base — a class of bug where
two independently-green PRs conflict when combined on main.

## `mergeStateStatus` Values

Query with:

```bash
gh pr view <PR-number> --json mergeStateStatus -q '.mergeStateStatus'
```

| Value | Meaning | Action |
|-------|---------|--------|
| `CLEAN` | All checks pass, branch up to date | Merge |
| `HAS_HOOKS` | Mergeable, pre-receive hooks will run | Merge (hooks run server-side) |
| `BEHIND` | Branch is behind main | Rebase, push, wait for CI |
| `BLOCKED` | Required checks failed or reviews missing | Investigate; do not force-merge |
| `UNKNOWN` | GitHub is computing merge status | Wait and re-query |
| `UNSTABLE` | Some non-required checks failed | Merge if required checks pass |
| `DIRTY` | Merge conflict exists | Resolve conflict, push, wait for CI |

## Recovery: BEHIND

Merge main into the feature branch (no force-push needed, since
`required_linear_history` is `false`):

```bash
git fetch origin
git checkout <branch>
git merge origin/main --no-edit
git push origin <branch>
```

After push, CI re-triggers automatically. Wait for all required checks (`ci-pass`,
`check-policy`) to pass before merging.

Using `git merge` instead of `git rebase` avoids force-push, which prevents stale
check results from appearing in the GitHub PR GUI (a known display issue where
old failed checks from the previous HEAD remain visible alongside new results).

## Sequential PR Merge Pattern

When merging multiple PRs in sequence, each merge into main advances the base.
Subsequent PRs become `BEHIND` even if they were `CLEAN` moments before.

Workflow:
1. Merge PR A (main advances)
2. PR B is now `BEHIND` — merge updated main into PR B's branch
3. Push PR B — CI re-runs
4. Wait for CI green on PR B, then merge

This is expected behavior, not an error. Budget time for the merge-CI cycle
when planning sequential merges.

## `enforce_admins` Limitations

`enforce_admins: true` in Branch Protection forces admins to follow protection
rules. This setting is enabled, but on personal repositories it does not reliably
block the repo owner's `--admin` bypass at the API level (GitHub limitation).

**Policy**: `--admin` is prohibited (see `pr-merge.md` Constraints). The correct
response to a blocked merge is always to diagnose the cause and fix it.
