# issue-create

## Purpose

Decompose a task into a structured GitHub Issue with specification, acceptance criteria, test plan, and risk assessment. This is the **entry point** of the Issue-driven workflow, replacing the former `task-plan` command.

Every implementation task starts here. The resulting Issue becomes the single source of truth for what to implement and when it is done.

## When to use

- Before `implement` — as the first step after `doctor`
- When a new feature, bug fix, or refactor needs to be planned and tracked
- When breaking down a large task into smaller implementable units

## Inputs (attach as `@...`)

- Task description or user requirement (required)
- Relevant ADRs (`@docs/adr/`) (recommended)
- Relevant schemas (`@docs/schemas/`) (recommended)
- Existing source files (`@R/...`) if known

## Steps

### 1. Analyze the task

Search the codebase to understand the change:

- Identify relevant ADRs and schemas
- Check existing code paths and patterns in `R/`
- Assess scope: single-file vs multi-file, single-module vs cross-module

### 2. Determine Issue granularity

Evaluate whether the task fits a single Issue or needs decomposition:

| Situation | Action |
|-----------|--------|
| Small, self-contained change (1 PR) | Create one Issue |
| Large feature spanning multiple areas | Create parent Issue + child Issues |
| Ambiguous scope | Create one Issue with investigation scope, then decompose after investigation |

**Ideal granularity**: 1 Issue = 1 PR = 1 reviewable unit of change.

### 3. Draft the Issue body

Structure the Issue using the project's Issue templates in `.github/ISSUE_TEMPLATE/`:

- **Bug fix** (`fix:`): Read `@.github/ISSUE_TEMPLATE/bug_report.md` and follow its sections.
- **All other types** (`feat:`, `refactor:`, `chore:`, `test:`, etc.): Read `@.github/ISSUE_TEMPLATE/task.md` and follow its sections.

**Always read the appropriate template file first** — do not infer the structure from recent Issues or from memory. The templates are the single source of truth for Issue structure.

The templates already include all required sections. At minimum, every Issue must have:

- **Summary**: 1-2 sentences describing the change
- **Motivation / Context**: why this is needed
- **Related ADR**: which ADR(s) govern this change
- **Schema Impact**: which schemas or S7 classes are affected
- **Acceptance Criteria (Definition of Done)**: 2-5 concrete, verifiable criteria
- **Test Plan**: concrete test cases that make the Issue self-contained (see Test Plan Guidelines below)
- **Risks / Open Questions**: anything that needs clarification

#### Test Plan Guidelines

The Test Plan must include **specific, executable test case examples** — not vague placeholders.
The goal is for the Issue to be self-contained: anyone reading it can understand exactly what to test without consulting other documents.

Each test case must specify:

| Column | Required | Description |
|--------|----------|-------------|
| Scenario | Yes | Descriptive name (e.g., "Valid 3-node linear graph") |
| Input / Precondition | Yes | **Concrete values** — not "valid input" but actual data (e.g., `nodes = list("A", "B"), edges = list(c("A", "B"))`) |
| Expected Result | Yes | **Specific outcome** — not "succeeds" but what exactly happens (e.g., "Returns DecisionGraph with 2 nodes and 1 edge") |
| Notes | Optional | Edge case rationale, boundary justification, related acceptance criteria |

Minimum coverage:

- At least **2 normal cases** with distinct inputs
- At least **2 error/validation cases** (e.g., NULL input, type mismatch, constraint violation)
- At least **1 boundary case** where applicable (e.g., empty collection, single element, max length)

**Anti-patterns to avoid**:

- `| Normal case | valid input | succeeds |` — too vague to be actionable
- `| Error case | invalid input | fails |` — does not specify what is invalid or how it fails
- Omitting the Test Plan entirely with "will be decided during implementation"

The Issue's Test Plan serves as the **initial test matrix** for the `test-create` command, which will expand it with additional equivalence partitions, boundary values, and implementation-specific cases.

### 4. Create the Issue on GitHub

```bash
gh issue create \
  --title "<type>: <short description>" \
  --body "$(cat <<'EOF'
<structured Issue body from Step 3>
EOF
)" \
  --label "<type>"
```

Title prefix must match the commit type convention: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `ci:`, `chore:`, etc.

### 5. Decompose into child Issues (if needed)

For large tasks, create child Issues and link them from the parent using a Task List:

```markdown
## Sub-issues

- [ ] #<child-issue-1>
- [ ] #<child-issue-2>
```

Each child Issue should be independently implementable (1 child = 1 PR).

### 6. Recommend next step

After Issue creation, suggest the implementation order:

```text
Issue #<N> created: <title>
Next: /implement with Issue #<N>
```

If cross-module integration is involved, recommend `/integration-design` before `/implement`.

## Output (response format)

- **Issue URL**: link to the created Issue
- **Related ADRs**: list of governing ADRs
- **Acceptance criteria**: numbered list (copied from Issue)
- **Test plan**: key scenarios
- **Files likely to change**: list of paths
- **Risks / open questions**: anything flagged
- **Sub-issues** (if decomposed): list of child Issue URLs

## Constraints

- Do NOT write code in this step. Code changes happen in `implement`.
- If requirements are unclear, ask the user before creating the Issue.
- Always use `gh issue create` to create the Issue (not manual GitHub UI).
- Issue title must follow the `<type>: <description>` convention.

## Related

- `@.cursor/commands/implement.md` (next step)
- `@.cursor/commands/integration-design.md` (when cross-module)
- `@.cursor/rules/workflow-policy.mdc`
