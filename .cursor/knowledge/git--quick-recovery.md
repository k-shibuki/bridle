---
trigger: lost commit, reflog, commit disappeared, rebase lost, push rejected, diverged branch, non-fast-forward, force-with-lease, force-with-lease failure, force-with-lease rejected, remote ref updated
---
# Quick Git Recovery

Short recovery procedures for common git issues. For complex scenarios (squash merge conflicts, branch interference), see the dedicated `git--*` atoms.

## Lost Commit After Rebase

**Symptom**: After a rebase (manual or subagent-triggered), commits seem to disappear from the branch.

```bash
# 1. Find the lost commit in reflog
git reflog --all | grep "<part-of-commit-message>"

# 2. Cherry-pick it back
git cherry-pick <found-sha>
```

## Force-with-Lease Rejected

**Symptom**: `git push --force-with-lease` fails with `remote rejected` or `stale info`. This typically occurs when a background process (subagent, prior push) updated the remote ref after the local tracking ref was last fetched.

```bash
# 1. Sync local tracking refs with remote
git fetch origin

# 2. Compare remote SHA with local HEAD
remote_sha=$(git ls-remote origin <branch> | awk '{print $1}')
local_sha=$(git rev-parse HEAD)

# 3a. If SHAs match: a prior push already succeeded, no action needed
# 3b. If SHAs differ: fetch updated the lease baseline, retry
git push --force-with-lease origin <branch>

# 3c. If retry also fails: another agent changed the branch
#     Re-identify boundary and re-rebase if needed (see git--squash-merge-dependent-branch.md)
git rebase --onto origin/main <new-boundary> <branch>
git push --force-with-lease origin <branch>
```

**Root cause pattern**: A background subagent's `git push` completes between your `git fetch` and `git push --force-with-lease`. The lease check compares against the stale local tracking ref, not the now-updated remote.

## Diverged Local and Remote

**Symptom**: `git push` is rejected because the remote has commits not in the local branch (e.g., from a squash merge of another PR).

```bash
# 1. Fetch latest
git fetch origin

# 2. Rebase onto updated main
git rebase origin/main

# 3. Resolve any conflicts, then push
git push --force-with-lease origin <branch>
```
