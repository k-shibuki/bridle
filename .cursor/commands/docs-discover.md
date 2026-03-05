# docs-discover

## Purpose

Identify which project documents are relevant to the current work, and ensure they get updated at the right time.

This command is designed to be usable both:

- Standalone (run it directly), and
- As an optional pre-commit step before running `commit` (recommended when changes are user-facing or contract-changing).

## When to use

- You changed behavior, APIs, data contracts, or workflows and documentation likely needs to follow.
- You are preparing to merge/ship and want to avoid "code changed but docs didn't".
- You have some docs attached and want to ensure all related docs are updated, not only one file.

## Modes

This command supports two modes depending on the stage:

- **Mode 1: Discover (early stage)**: identify candidate docs and request missing attachments; do **not** edit docs yet if the change is not finalized.
- **Mode 2: Update (pre-commit stage)**: update the chosen docs and report edits; this is the "make it real" step.

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

## Steps

1. List candidate docs (file paths) and explain why each is relevant.
2. Decide which docs must be updated vs can be skipped (with reasons).
3. If in **Mode 1 (Discover)**:
   - Ask the user to attach the missing `@docs/...` files you need.
   - Stop after discovery (no doc edits yet).
4. If in **Mode 2 (Update)**:
   - Apply doc updates (edit files) with:
     - What changed (bullets)
     - Why (if non-obvious)
     - Any user-facing impact or migration notes
   - Report what was updated and what was intentionally left unchanged.

## Output (response format)

- **Candidates**: list of doc paths + relevance signal(s)
- **Chosen docs to update**: list + rationale
- **Edits made**: per doc file, bullet summary
- **Skipped docs**: list + reason

## Related rules

- `@.cursor/rules/integration-design.mdc` (when changes affect cross-module contracts / data flow docs)
