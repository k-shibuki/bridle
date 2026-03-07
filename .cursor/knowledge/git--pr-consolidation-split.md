---
trigger: PR consolidation, multiple issues one PR, split PR, 1:1 principle
---
# PR Consolidation: Accept or Split

**Symptom**: A single branch/PR contains work for multiple Issues due to branch confusion.

## Option A: Accept consolidation (simpler)

1. Update the PR title and body to reference all Issues
2. Add `Closes #N` for each Issue in the PR body
3. Close any orphaned PRs with "Superseded by #XX"

## Option B: Split into separate PRs (cleaner)

1. Identify commit ranges for each Issue
2. Create new branches from main for each
3. Cherry-pick the relevant commits to each branch
4. Create new PRs; close the consolidated one

**Decision criteria**: Use Option A when the Issues are closely related and the PR is already passing CI. Use Option B when the Issues are independent and reviewers need separate review scopes.
