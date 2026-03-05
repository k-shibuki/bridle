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

- `@.cursor/rules/integration-design.mdc`

This command focuses on the concrete deliverables and how to produce them.

## Steps (deliverables)

1. Produce a Mermaid sequence diagram and save it under `docs/` (e.g., `docs/sequences/`).
2. Define shared data contracts as S7 classes in `R/{class_name}.R`.
3. If introducing new parameters/fields, create a **propagation map** (where the value is accepted, transformed, forwarded, and where it has effect).
4. Add integration tests at `tests/testthat/test-{feature}-integration.R` that validate the end-to-end flow (including the propagation map checkpoints).
   - For instrumentation conventions (log format, template), see `@.cursor/rules/debug.mdc` Section 2
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

## Related

- `@.cursor/rules/integration-design.mdc` (policy)
- `@.cursor/commands/debug.md` (for instrumentation procedures)
