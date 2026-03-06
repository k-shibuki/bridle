# implement

## Purpose

Implement the selected task (code changes only; no tests in this step).

## When to use

- After creating an Issue with `issue-create` and agreeing on an implementation plan
- Any time you need to implement a scoped change that is already tracked by an Issue

## Inputs (ask if missing)

- **Issue number** (required): the GitHub Issue to implement (e.g., `#42`)
- Any context documents the user wants to provide (requirements, specs, plans, etc.)
- Any relevant source files (`@R/...`) if the user already knows them

**Note**: Specific document attachments are optional. This command will actively search the codebase for necessary context.

## Constraints

- Use repo search tools (e.g., `grep`, semantic search) to find necessary context rather than guessing or asking the user for every file.
- All implementation work must be traceable to the Issue. If the scope drifts, update the Issue or create a new one.

## Steps

1. **Retrieve the Issue specification**:
   ```bash
   gh issue view <issue-number>
   ```
   Extract: summary, acceptance criteria (DoD), test plan, schema impact, and related ADRs.

2. **Confirm scope** based on:
   - The Issue's acceptance criteria
   - Attached documents (if any)
   - User instructions

3. **Actively search the codebase** to understand:
   - Existing code paths and patterns
   - Related modules and dependencies
   - Coding conventions used in the project

4. If the change touches interfaces/contracts across modules (APIs, schemas, request/response shapes, new parameters that must propagate), consider switching to `NEXT_COMMAND: /integration-design` to design and verify the flow.

5. Verify the development container is running (`make doctor`). If not, start it with `make container-up`.

6. Identify the minimal set of files to change.

7. Implement the change.

8. Do a quick sanity check (basic execution path review; avoid long-running processes unless requested).

## Output (response format)

- **Issue**: `#<number>` — title
- **Scope recap**: what changed (1-3 bullets)
- **Files changed**: list of paths
- **DoD progress**: which acceptance criteria are now met
- **Context discovered**: key files/patterns found via search (if relevant)
- **Notes**: any trade-offs, follow-ups, or risks

## Related

- `@.cursor/commands/issue-create.md` (previous step)
- `@.cursor/commands/test-create.md` (next step)
- `@.cursor/rules/ai-guardrails.mdc`
- `@.cursor/rules/integration-design.mdc` (when changes span module boundaries / contracts)
