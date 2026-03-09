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

```bash
git fetch origin
git checkout <branch>
git rebase origin/main
git push --force-with-lease origin <branch>
```

After push, CI re-triggers automatically. Wait for all required checks (`ci-pass`,
`check-policy`) to pass before merging.

## Sequential PR Merge Pattern

When merging multiple PRs in sequence, each merge into main advances the base.
Subsequent PRs become `BEHIND` even if they were `CLEAN` moments before.

Workflow:
1. Merge PR A (main advances)
2. PR B is now `BEHIND` — rebase onto updated main
3. Push PR B — CI re-runs
4. Wait for CI green on PR B, then merge

This is expected behavior, not an error. Budget time for the rebase-CI cycle
when planning sequential merges.

## Admin Bypass and `enforce_admins`

`enforce_admins: true` in Branch Protection forces admins to follow all protection
rules (status checks, reviews, etc.). This setting is enabled on this repository.

The `gh pr merge --admin` flag is designed to bypass protection rules. With
`enforce_admins: true`, GitHub should reject admin bypass attempts. However,
the interaction between `--admin` and `strict: true` has edge cases where
the bypass may succeed for the up-to-date requirement while status checks
are still enforced.

**Policy**: Do not use `--admin` flag. Instead, follow the BEHIND recovery
procedure above. The correct fix for a BEHIND branch is always rebase + CI,
never an admin override.
