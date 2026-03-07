---
trigger: lost commit, reflog, commit disappeared, rebase lost, push rejected, diverged branch, non-fast-forward, force-with-lease
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
