# task-plan

## Purpose

Define scope, acceptance criteria, and implementation steps before writing code.

## When to use

- Before `implement` — as the first step after `doctor`
- When a task is ambiguous or spans multiple modules

## Inputs (attach as `@...`)

- Task description or issue reference (required)
- Relevant ADRs (`@docs/adr/`) (recommended)
- Relevant schemas (`@docs/schemas/`) (recommended)
- Existing source files (`@R/...`) if known

## Steps

1. **Understand the task**: read attached context and search the codebase for related code.
2. **Identify relevant ADRs and schemas**: list which ADRs govern the feature and which schemas are affected.
3. **Define acceptance criteria**: 2-5 concrete, verifiable criteria.
4. **List files to change**: identify the minimal set of files (existing and new).
5. **Plan implementation steps**: ordered list of steps, each small enough for one `implement` cycle.
6. **Identify risks**: integration points, breaking changes, or unclear requirements.

## Output (response format)

- **ADRs**: list of relevant ADRs
- **Acceptance criteria**: numbered list
- **Files**: list of files to create/modify
- **Steps**: ordered implementation plan
- **Risks / open questions**: anything that needs clarification

## Constraints

- Do NOT write code in this step. Code changes happen in `implement`.
- If requirements are unclear, ask the user before producing the plan.
- For changes spanning module boundaries, recommend running `integration-design` before `implement`.

## Related

- `@.cursor/commands/implement.md` (next step)
- `@.cursor/commands/integration-design.md` (when cross-module)
- `@.cursor/rules/ai-guardrails.mdc`
