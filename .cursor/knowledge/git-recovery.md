# Git Recovery Playbook

Recovery procedures for common git state corruption scenarios in AI-driven development.

**Policy**: See `@.cursor/rules/ai-guardrails.mdc` § Git conflict prevention for enforceable rules.

---

## Scenario 1: Subagent Branch Interference

**Symptom**: A subagent ran `git checkout main` or `git switch`, changing the main agent's working branch. Commits intended for branch A end up on branch B.

**Prevention** (mandatory — see ai-guardrails.mdc):
- Subagent prompts for CI-wait/merge MUST include: "Do NOT run git checkout, git switch, git branch -d, or git rebase"
- Subagents should use only `gh` API commands (e.g., `gh pr merge`), never local git commands

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

---

## Scenario 2: Commit Lost After Rebase

**Symptom**: After a rebase (manual or subagent-triggered), commits seem to disappear from the branch.

**Recovery**:

```bash
# 1. Find the lost commit in reflog
git reflog --all | grep "<part-of-commit-message>"

# 2. Cherry-pick it back
git cherry-pick <found-sha>
```

---

## Scenario 3: PR Consolidation (1:1 Principle Broken)

**Symptom**: A single branch/PR contains work for multiple Issues due to branch confusion.

**Options**:

### Option A: Accept consolidation (simpler)
1. Update the PR title and body to reference all Issues
2. Add `Closes #N` for each Issue in the PR body
3. Close any orphaned PRs with "Superseded by #XX"

### Option B: Split into separate PRs (cleaner)
1. Identify commit ranges for each Issue
2. Create new branches from main for each
3. Cherry-pick the relevant commits to each branch
4. Create new PRs; close the consolidated one

**Decision criteria**: Use Option A when the Issues are closely related and the PR is already passing CI. Use Option B when the Issues are independent and reviewers need separate review scopes.

---

## Scenario 4: Diverged Local and Remote

**Symptom**: `git push` is rejected because the remote has commits not in the local branch (e.g., from a squash merge of another PR).

**Recovery**:

```bash
# 1. Fetch latest
git fetch origin

# 2. Rebase onto updated main
git rebase origin/main

# 3. Resolve any conflicts, then push
git push --force-with-lease origin <branch>
```

---

## Prevention Checklist

- [ ] Subagent prompts explicitly prohibit `git checkout`, `git switch`, `git rebase`
- [ ] Main agent and subagent work on **different branches**
- [ ] Before starting work, run `git status` to detect unexpected state
- [ ] After subagent completion, verify branch state before continuing
- [ ] Use `--force-with-lease` (never `--force`) when force-pushing
