# integration-design

## Purpose

Design and verify cross-module integration (interfaces, types, and data flow).

## When to use

- A feature spans multiple modules and breaks when combined
- There is a type/contract mismatch between modules
- A refactor changes public interfaces

## Inputs (attach as `@...`)

- Any context documents (ADRs, specs, design docs) relevant to the integration
- The involved modules/files (`@R/...`) if known
- Any failing logs/scripts/tests (`@tests/...`) if available

**Note**: Specific document attachments are optional. This command will search the codebase to discover involved modules, existing contracts, and integration points.

## Policy (rules)

Follow the integration policy here:

- `@.cursor/rules/integration-strategy.mdc`

This command focuses on the concrete deliverables and how to produce them.

## Pre-Implementation Checks

1. **Specification review**: Check relevant ADRs in `docs/adr/` and `DESCRIPTION`; verify implementation proposal meets spec
2. **Codebase understanding**: Investigate related modules in `R/`, verify no circular dependencies, check naming/error-handling consistency
3. **Coding conventions**: Comments in English, roxygen2 for documentation (`#' @param`, `#' @return`, `#' @export`)

## Steps (deliverables)

1. Produce a Mermaid sequence diagram and save it under `docs/` (e.g., `docs/sequences/`). Explicitly specify data types (S7 classes recommended).
2. Define shared data contracts as S7 classes in `R/{class_name}.R`.
3. If introducing new parameters/fields, create a **propagation map** (where the value is accepted, transformed, forwarded, and where it has effect).
4. Add integration tests at `tests/testthat/test-{feature}-integration.R` that validate the end-to-end flow (including the propagation map checkpoints).
   - For instrumentation conventions (log format, template), see `@.cursor/rules/debug-strategy.mdc` Section 2
5. Run/verify the flow and update the sequence diagram to match reality.

## Output (response format)

- **Sequence diagram**: Mermaid
- **Data contracts**: S7 class definitions
- **Propagation map** (if applicable): short table/bullets mapping boundaries and sinks
- **Integration tests**: runnable tests + how to run them
- **Verification**: what was checked and results

## Notes

### Execution environment

- **Tests**: Use `make test` or `Rscript -e "devtools::test(filter = 'feature')"`.
- Run from package root.

## Checklists

### Pre-Implementation
- [ ] Specification review (docs/adr/, DESCRIPTION)
- [ ] Codebase understanding
- [ ] Dependency verification
- [ ] Coding convention check

### Design & Implementation
- [ ] Sequence diagram created
- [ ] S7 classes defined
- [ ] **Propagation table for added parameters/fields** (where received, where passed, where effect occurs)
- [ ] Integration tests created and executed
- [ ] Integration tests verify **each boundary in propagation table** (place observation points that fail if not wired)
- [ ] R CMD check passes

### Post-Implementation
- [ ] Specification compliance verified
- [ ] Comment language verified
- [ ] Consistency verified
- [ ] Lint errors verified (lintr, styler)

## Related

- `@.cursor/rules/integration-strategy.mdc` (policy)
- `@.cursor/commands/debug.md` (for instrumentation procedures)
