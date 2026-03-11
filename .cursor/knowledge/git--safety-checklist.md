---
trigger: git safety, concurrent agent, pre-work verification, force-with-lease, PR auto-close, base branch deleted
---
# Git Safety Checklist for Concurrent Agent Work

Run before starting any work when multiple agents may be active:

- [ ] Subagent prompts explicitly prohibit `git checkout`, `git switch`, `git rebase` (exception: "Dependent PR Merge Chain" template allows scoped `--onto` rebase)
- [ ] Main agent and subagent work on **different branches**
- [ ] Before starting work, run `git status` to detect unexpected state
- [ ] After subagent completion, verify branch state before continuing:
  - `git fetch origin` to sync tracking refs
  - `git ls-remote origin <branch>` to confirm remote ref matches expected SHA
  - If subagent pushed: `gh pr view <N> --json headRefOid -q '.headRefOid'` to verify PR head matches
  - If mismatch: see `git--quick-recovery.md` § Force-with-Lease Rejected
- [ ] Avoid force-push in the normal PR flow — use new commits, not `amend` + force-push. When force-push is unavoidable (recovery scenarios like `--onto` rebase), use `--force-with-lease` (never `--force`)
- [ ] Never use `--admin` on `gh pr merge` — diagnose the block instead
- [ ] PRs always target `main` (never `--base feat/<branch>`)

## PR Auto-Close Prevention

**Symptom**: A PR targeting `feat/A-branch` is auto-closed by GitHub when PR #A is merged (branch auto-deleted by `delete_branch_on_merge` setting).

**Cause**: GitHub auto-closes PRs whose base branch is deleted.

**Prevention**: Always use `--base main` (see `HS-PR-BASE`).

**Recovery**:

1. Rebase the orphaned branch onto `origin/main`
2. Force push: `git push --force-with-lease origin <branch>`
3. Create a new PR with `--base main`
4. Close the auto-closed PR with a comment: "Superseded by #XX"
