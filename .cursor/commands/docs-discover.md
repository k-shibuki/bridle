# docs-discover

## Purpose

Identify which project documents are relevant to the current work, and ensure they get updated at the right time.

This command is called **twice** in the standard workflow, at different stages with different goals:

| Invocation | When | Mode | Goal |
|------------|------|------|------|
| 1st | During `implement` (Step 3) | Mode 1: Discover | Identify affected docs early, before code is finalized |
| 2nd | Before `commit` | Mode 2: Update | Apply doc edits to match the finalized code change |

It can also be run standalone at any time.

## When to use

- **(Mode 1)** You are about to implement a change and want to know which docs will need updating. Called automatically by `implement` during context discovery.
- **(Mode 2)** You finished implementation + tests + quality checks and are about to commit. This is the "make it real" step — apply doc edits so code and docs ship together.
- **(Standalone)** You have some docs attached and want to ensure all related docs are updated, not only one file.

## Modes

### Mode 1: Discover (early stage — during `implement`)

- Identify candidate docs that are likely affected by the upcoming change.
- Do **not** edit docs yet — the implementation is not finalized.
- Output a doc impact list that carries forward to Mode 2.
- If docs need user-provided context (e.g., ADR attachments), ask for it now.

### Mode 2: Update (pre-commit stage — before `commit`)

- Review the diff (`git diff --stat`) against the doc impact list from Mode 1.
- Apply doc updates (edit files) for docs that need to change.
- Report what was updated and what was intentionally left unchanged.
- If Mode 1 was skipped, perform discovery and update in one pass.

## Inputs (attach as `@...`)

- Any docs you already know are relevant (`@docs/...`) (recommended)
- ADRs (`@docs/adr/`) (recommended)
- Optional: code context (`@R/...`) and/or diff summary (`git diff --stat` output)

## Discovery heuristics (how to find related docs)

Use multiple signals (don't rely on one):

1. **Attached docs**: any `@docs/...` attached by the user are always candidates.
2. **Changed areas**: use the current diff to list touched modules/paths (e.g. `git diff --name-only`, `git diff --stat`).
3. **Repository docs search**:
   - Start under `docs/` and search for keywords (module names, feature names, API names).
   - If the repo has ADRs (`docs/adr/`), consider them if the change touches those areas.
4. **R package docs**:
   - `DESCRIPTION` — package metadata, dependencies
   - `README.md` — package overview
   - `NEWS.md` — changelog (update when releasing)
   - `man/` — function documentation (roxygen2-generated; update roxygen2 comments in `R/`)
   - `vignettes/` — long-form user documentation
5. **Makefile / Scripts**: if you changed `Makefile` or scripts:
   - Check `README.md` for accuracy.
   - Update related Cursor commands (e.g., `test-create.md`, `quality-check.md`) if command usage changed.
6. **Cursor workflow docs**: if you changed `.cursor/commands/` or `.cursor/rules/`:
   - Check `.cursor/README.md` for accuracy (workflow diagram, command table, rules table).

## Steps

### Mode 1 (Discover)

1. List candidate docs (file paths) and explain why each is relevant.
2. Categorize each as: **must update**, **likely update**, or **no change expected** (with reasons).
3. If user-provided context is needed (e.g., specific ADR attachments), ask for it.
4. Output the **doc impact list** (carries forward to Mode 2).

### Mode 2 (Update)

1. Review the finalized diff (`git diff --stat`, `git diff`).
2. If a Mode 1 doc impact list exists, use it as the starting point. Otherwise, perform discovery first.
3. For each doc that needs updating:
   - Apply edits with clear rationale (what changed, why, user-facing impact).
4. Report what was updated and what was intentionally left unchanged.
5. If no docs need updating, explicitly state "No docs updates needed" so `commit` can proceed.

## Output (response format)

### Mode 1

- **Doc impact list**: table of doc paths + relevance + expected action (must/likely/skip)
- **Missing context**: what attachments are needed from the user

### Mode 2

- **Candidates**: list of doc paths + relevance signal(s)
- **Chosen docs to update**: list + rationale
- **Edits made**: per doc file, bullet summary
- **Skipped docs**: list + reason

## Related

- `@.cursor/commands/implement.md` (calls Mode 1 during Step 3)
- `@.cursor/commands/commit.md` (calls Mode 2 before committing)
- `@.cursor/rules/integration-design.mdc` (when changes affect cross-module contracts / data flow docs)
