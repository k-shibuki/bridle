# Template: Dependent PR Merge Chain (rebase-enabled)

```text
## Goal
Merge PRs #<A> and #<B> sequentially. #<B> was branched from #<A>, so after
squash-merging #<A>, use `git rebase --onto` to rebase #<B> cleanly.

## Steps

1. Poll CI for PR #<A> using Adaptive Polling Strategy from `ci--job-dependency-graph.md` § Adaptive Polling Strategy:
2. Merge PR #<A>: `gh pr merge <A> --squash`
3. Verify: `gh pr view <A> --json state -q '.state'` → "MERGED"
4. Check PR #<B> mergeability: `gh pr view <B> --json mergeable -q '.mergeable'`
5. If CONFLICTING, rebase #<B> onto updated main:
   a. `git fetch origin main`
   b. `git checkout <branch-B>`
   c. Identify commits to keep (only #<B>'s own commits, not #<A>'s):
      `git log --oneline origin/main..<branch-B>`
   d. Find the boundary (last commit from #<A>):
      The commit just before #<B>'s first unique commit.
   e. `git rebase --onto origin/main <boundary-commit> <branch-B>`
   f. `git push --force-with-lease origin <branch-B>`
   g. Verify push reached remote:
      `git ls-remote origin <branch-B> | awk '{print $1}'` must equal `git rev-parse HEAD`
      If mismatch, see Error handling § force-with-lease rejected.
6. Poll CI for PR #<B> using Adaptive Polling Strategy from `ci--job-dependency-graph.md` § Adaptive Polling Strategy:
7. STOP — report CI status and rebased HEAD to main agent.
   The main agent MUST run `pr-review` on the rebased HEAD before merge.
   Do NOT merge PR #<B> directly — the rebase changed the commit history,
   and the previous review (if any) was on a different HEAD.

## Git operations allowed (scoped)
- `git fetch origin main` — read-only sync
- `git checkout <branch-B>` — only the specific branch listed above
- `git rebase --onto origin/main <commit> <branch-B>` — targeted rebase
- `git push --force-with-lease origin <branch-B>` — only the rebased branch

## Prohibitions
- NEVER push to main directly
- NEVER merge PR #<B> after rebase — the main agent must run `pr-review` first
- NEVER use `git push --force` (without `--force-with-lease`)
- NEVER modify files or create new commits — only rebase existing commits
- NEVER run `pr-review` or `review-fix` — these are Tier 3 (main agent only)

## Error handling
- If CI fails on either PR: stop, report which check failed and the details URL
- If rebase --onto has conflicts: abort rebase (`git rebase --abort`), report the conflicting files
- If merge fails: report the error, do NOT retry
- If merge blocked by unresolved review threads: report "BLOCKED: unresolved review threads — run review-fix per review--consensus-protocol.md"
- If `git push --force-with-lease` is rejected:
  1. `git fetch origin` to sync tracking refs
  2. Compare remote SHA (`git ls-remote origin <branch-B>`) with local `HEAD` (`git rev-parse HEAD`)
  3. If SHAs match (prior push already succeeded): no further action needed
  4. If SHAs differ: retry `git push --force-with-lease` (fetch updated the lease baseline)
  5. If retry also fails: abort, report the conflict (see `git--quick-recovery.md`)

## Return format
Report:
- PR #<A>: merged (yes/no), merge SHA
- PR #<B>: CI status (pass/fail/pending), rebased HEAD: <sha>
- Branch #<B> post-rebase HEAD: <sha> (from `git rev-parse HEAD`)
- Push verification: remote SHA matches local HEAD (yes/no)
- Next action required: main agent runs `pr-review` on PR #<B>
- Any errors encountered
```
