---
trigger: docs discovery, documentation heuristics, doc impact list, related docs search
---
# Documentation Discovery Heuristics

How to identify which project documents are affected by a code change.
Used during implementation (early discovery) and before commit (update pass).

## Two Passes

| Pass | When | Goal |
|------|------|------|
| **Discovery** (during `implement`) | Before code is finalized | Identify candidate docs; build doc impact list |
| **Update** (during `commit`) | After code is finalized | Apply doc edits so code and docs ship together |

Discovery produces a doc impact list that carries forward to the update pass.

## Six Discovery Signals

Use multiple signals (don't rely on one):

1. **Attached docs**: any `@docs/...` attached by the user are always candidates.
2. **Changed areas**: use the current diff to list touched modules/paths
   (`git diff --name-only`, `git diff --stat`).
3. **Repository docs search**:
   - Search under `docs/` for keywords (module names, feature names, API names).
   - Consider ADRs (`docs/adr/`) if the change touches those areas.
4. **R package docs**:
   - `DESCRIPTION` — package metadata, dependencies
   - `README.md` — package overview
   - `NEWS.md` — changelog (update when releasing)
   - `man/` — function documentation (roxygen2-generated; update roxygen2 comments in `R/`)
   - `vignettes/` — long-form user documentation
5. **Makefile / Scripts**: if you changed `Makefile` or scripts:
   - Check `README.md` for accuracy.
   - Update related Cursor commands if command usage changed.
6. **Cursor workflow docs**: if you changed `.cursor/commands/` or `.cursor/rules/`:
   - Check `docs/agent-control/` for consistency (architecture, FSM, evidence schema).

## Impact Classification

For each candidate doc:

| Category | Meaning |
|----------|---------|
| **Must update** | Doc directly describes changed behavior |
| **Likely update** | Doc references changed area indirectly |
| **No change expected** | Doc is tangentially related |

## Related

- `commit-format.mdc` — commit policy (docs ship with code)
- `docs/agent-control/architecture.md` — control system architecture
