---
trigger: subagent branch, misplaced commit, git checkout interference, cherry-pick recovery, commit on wrong branch
---
# Subagent Branch Interference Recovery

**Symptom**: A subagent ran `git checkout main` or `git switch`, changing the main agent's working branch. Commits intended for branch A end up on branch B.

**Prevention** (per `@.cursor/rules/subagent-policy.mdc` § Prompt structure):

- Subagent prompts for CI-wait/merge should include git operation prohibitions ("Do NOT run git checkout, git switch, git branch -d, or git rebase")
- Subagents should use only `gh` API commands (e.g., `gh pr merge`), not local git commands

**Recovery**:

```bash
# 1. Identify the misplaced commits
git log --oneline -10

# 2. Note the commit SHAs that belong to the other branch

# 3. Switch to the correct branch (or create it)
git checkout -b feat/<N>-correct-branch main

# 4. Cherry-pick the misplaced commits
git cherry-pick <sha1> <sha2>

# 5. If the original branch needs cleanup, reset it
git checkout original-branch
git reset --hard <last-good-sha>
git push --force-with-lease origin original-branch
```
