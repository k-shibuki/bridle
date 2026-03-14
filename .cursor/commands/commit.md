# commit

## Reads
- `commit-format.mdc` (message format, branch naming, atomic commits policy)
- `workflow--docs-discovery-heuristics.md` (pre-commit doc alignment)

## Sense

State (branch, uncommitted files) is already known from `next`. Read the diff content for commit message composition:

```bash
git diff --stat
git diff
```

## Act

1. **Doc alignment (Mode 2)**: Review finalized diff against the doc impact list from `implement`. Apply doc updates per `workflow--docs-discovery-heuristics.md`. If no docs need updating, state "No docs updates needed" and proceed.
2. Stage and commit per `commit-format.mdc` (format, footer with `Refs: #<issue>`). Split into atomic commits when beneficial per § Atomic Commits.
3. Do not open interactive editor (`git commit` without `-m`). English only.

### Exception: documentation-only direct push

For docs-only changes (type: `docs` + exception: `no-issue`), direct push to `main` is permitted. If the change touches any code, CI config, or Makefile logic: use `pr-create` instead.

## Output
- Branch: current branch name
- Issue: `#<number>` referenced
- Commits: list (message + short hash)
- Summary: `git log --oneline -n <count>`

## Guard
- `commit-msg` hook validates format
- `HS-NO-SKIP`: every commit references an Issue (except hotfix/docs exceptions per `commit-format.mdc` § Footer)
