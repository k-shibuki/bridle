---
trigger: squash merge conflict, rebase --onto, dependent branch, dependent PR
---
# Squash Merge Creates Conflicts for Dependent Branches

**Symptom**: PR #A is squash-merged into main. PR #B (branched from #A's feature branch) cannot rebase onto main — conflicts appear on every file that #A touched, even though the content is identical.

**Cause**: Squash merge creates a single new commit on main that combines all of #A's commits. Git does not recognize #A's original commits as ancestors of the squash commit. When #B tries to rebase, git attempts to re-apply #A's commits on top of the squash, causing conflicts.

**Fix: `git rebase --onto`**

The `--onto` flag tells git to transplant only #B's unique commits, skipping the commits that came from #A:

```bash
# 1. Fetch latest main (which now contains #A's squash commit)
git fetch origin main

# 2. Identify commits on #B's branch
git log --oneline origin/main..feature-B
# Output example:
#   ccc3333 feat: B's own change      ← keep this
#   bbb2222 fix: A's second commit    ← skip (already in main via squash)
#   aaa1111 feat: A's first commit    ← skip (already in main via squash)

# 3. Find the boundary: the last commit from #A (the one just before #B's first unique commit)
# In the example above, bbb2222 is the boundary.

# 4. Rebase --onto: transplant only #B's commits onto main
git rebase --onto origin/main bbb2222 feature-B

# 5. Force push the rebased branch
git push --force-with-lease origin feature-B

# 6. Verify the push reached the remote
git ls-remote origin feature-B | head -1
# Compare the SHA with: git rev-parse HEAD
# They must match. If not, see git--quick-recovery.md § Force-with-Lease Rejected.
```

**Key insight**: The boundary commit is the last commit on #B's branch that originated from #A. Everything after it is #B's own work.

**Post-push verification**: Always confirm the remote ref matches `HEAD` after a force push. Background processes or concurrent agents can cause the push to silently fail the lease check. If `git ls-remote` shows a different SHA, fetch and retry (see `git--quick-recovery.md`).
