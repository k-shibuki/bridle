# commit

## Purpose

Create git commit(s) with **English message(s)** in the project's standard format.

## When to use

- After tests pass and you're ready to record changes (typically after `regression-test`)

## Policy (rules)

Follow the commit message policy here:

- `@.cursor/rules/commit-message-format.mdc`

This command intentionally avoids duplicating the policy (format/prefixes/language). Keep `commit-message-format.mdc` as the single source of truth.

## Issue reference (required)

Every commit must reference its tracking Issue in the footer:

```
Refs: #<issue-number>
```

**Exceptions**: `hotfix` or `docs-only` changes that bypass the Issue-driven flow may omit the Issue reference, but must state the justification in the commit body.

## Atomic commits (recommended)

Split changes into **logically cohesive, minimal commits** when beneficial:

| Split when | Keep together when |
|------------|-------------------|
| Multiple unrelated fixes in one session | Tightly coupled changes that break if separated |
| Refactor + feature in same diff | Single logical change across multiple files |
| Docs update independent of code change | Code + its corresponding test |

**Judgment criteria**:

- Each commit should be independently meaningful and pass tests
- Prefer 2-4 focused commits over 1 large commit or 10+ micro-commits
- When in doubt, fewer commits is safer

## Documentation alignment (required)

Before committing, run **docs-discover (Mode 2)** to ensure documentation is aligned with the change:

1. Review the finalized diff against the doc impact list from `implement` (Mode 1).
2. Apply any necessary doc updates (ADRs, README, Cursor commands/rules, DESCRIPTION, etc.).
3. If no docs changes are needed, explicitly state "No docs updates needed" and proceed.

See `@.cursor/commands/docs-discover.md` for the full procedure.

## Workflow

```bash
git branch --show-current
git status --short

if [ -z "$(git status --porcelain)" ]; then
    echo "No changes to commit"
    exit 0
fi

git diff --stat
git diff
```

### Single commit (simple case)

```bash
git add -A
git commit -m "<type>(<scope>): <summary>

- Change item 1
- Change item 2

Refs: #<issue-number>"
```

### Multiple commits (when splitting)

```bash
git add <specific-files>
git commit -m "<type>(<scope>): <summary-1>

- Change item
Refs: #<issue-number>"

git add <specific-files>
git commit -m "<type>(<scope>): <summary-2>

- Change item
Refs: #<issue-number>"
```

## Constraints

- Do **not** open an interactive editor (`git commit` without `-m`).
- Keep messages **English only**.
- Include `Refs: #<issue>` in every commit (except hotfix/docs-only exceptions).

## Output (response format)

- **Branch**: current branch name
- **Issue**: `#<number>` being referenced
- **Commits**: list of commits created (message + short hash for each)
- **Summary**: `git log --oneline -n <count>` showing the new commits

## Related

- `@.cursor/rules/commit-message-format.mdc`
- `@.cursor/commands/docs-discover.md` (Mode 2: pre-commit doc alignment)
- `@.cursor/commands/pr-create.md` (next step: PR flow)
- `@.cursor/commands/push.md` (exception flow only: docs-only direct push)
