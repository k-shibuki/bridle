# issue-review

## Purpose

Review existing GitHub Issues for quality, consistency, and implementability. Identify defects (missing fields, stale dependencies, ADR misalignment, ambiguous test plans) and produce an actionable improvement plan.

**This command produces a review report and applies fixes.** It does not create new Issues — use `issue-create` for that.

## When to use

- Before starting a batch of `implement` work (pre-flight review)
- After a design change (ADR update, schema change) to verify Issue alignment
- When `next` detects multiple open Issues and needs to assess readiness
- Periodically as a hygiene check

## Inputs

- Issue scope: `--all` (default), `--issue <N>`, or `--label <label>`
- Relevant ADRs (`@docs/adr/`) (auto-discovered)
- Relevant schemas (`@docs/schemas/`) (auto-discovered)
- Existing source files (`@R/...`) (auto-discovered)

## Steps

### 1. Gather Issues

```bash
# All open Issues (default)
gh issue list --state open --json number,title,labels,body,assignees,milestone --limit 50

# Or scoped
gh issue view <N> --json number,title,labels,body,assignees,milestone
```

### 2. Gather project context (parallel)

Run these in parallel to build the review context:

```bash
# ADRs
ls docs/adr/

# Schemas
ls docs/schemas/

# Existing R source
ls R/

# Existing tests
ls tests/testthat/

# Existing helper-mocks
cat tests/testthat/helper-mocks.R
```

Read relevant ADRs and schemas referenced by the Issues.

### 3. Per-Issue quality checklist

Evaluate each Issue against these criteria:

| # | Category | Check | Severity |
|---|----------|-------|----------|
| 1 | **Structure** | Has Summary, Motivation, Related ADR, Acceptance Criteria, Test Plan | Error |
| 2 | **ADR alignment** | Referenced ADR(s) exist and Issue spec does not contradict them | Error |
| 3 | **Schema consistency** | If Issue touches data structures, corresponding schema is referenced | Error |
| 4 | **Test Plan quality** | Concrete inputs/outputs per `issue-create` Test Plan Guidelines (no vague "valid input / succeeds") | Error |
| 5 | **Acceptance Criteria** | Verifiable (not subjective), 2-5 items | Warning |
| 6 | **Dependencies** | Referenced dependency Issues exist and are correctly numbered | Error |
| 7 | **Dependency freshness** | Dependency Issues are not already closed (stale reference) | Warning |
| 8 | **File predictions** | "Files likely to change" section is present and plausible | Warning |
| 9 | **S7 type safety** | If new S7 classes are proposed, explicit types are mentioned (no `class_any`) | Warning |
| 10 | **Mock strategy** | If LLM or external calls are involved, mock approach is documented | Warning |
| 11 | **Scope** | Issue is implementable in 1 PR (not too large) | Warning |
| 12 | **Title convention** | Follows `<type>: <description>` format | Warning |

### 4. Cross-Issue analysis

Beyond per-Issue checks, evaluate the Issue set as a whole:

| # | Category | Check |
|---|----------|-------|
| 1 | **Dependency graph** | No circular dependencies; dependency order is achievable |
| 2 | **Interface contracts** | Issues that produce/consume shared data structures agree on types |
| 3 | **Shared logic** | Common logic needed by multiple Issues is identified (not duplicated) |
| 4 | **Coverage gaps** | No important component is missing an Issue |
| 5 | **Parallel opportunities** | Independent Issues that can be worked on simultaneously are identified |
| 6 | **helper-mocks.R plan** | Mock functions needed across Issues are identified |

### 5. Classify findings

Split findings into two categories:

#### Category A: Actionable improvements (fix immediately)

Improvements that can be applied without design discussion:

- Missing or incorrect section headings
- Stale dependency references (closed Issues)
- Vague test plan entries that can be made concrete
- Missing mock strategy that follows established patterns
- Title convention fixes
- Missing "Files likely to change" entries

Apply these fixes via `gh issue edit` immediately.

#### Category B: Discussion required

Changes that require design decisions or user input:

- Interface contract disagreements between Issues
- Scope concerns (Issue too large, needs splitting)
- ADR gaps (behavior not covered by any ADR)
- Shared logic extraction (where to put it, API design)
- Technology choices (e.g., structured output vs text parsing)
- Security/sandboxing decisions

Present these as numbered discussion points with context and options.

### 6. Apply Category A fixes

For each actionable fix:

```bash
gh issue edit <N> --body "$(cat <<'EOF'
<updated Issue body>
EOF
)"
```

Report what was changed and why.

### 7. Present Category B for discussion

Format discussion points:

```
## Discussion Required

### D1: <topic>
- **Affects**: Issue #X, #Y
- **Current state**: <what the Issues say now>
- **Problem**: <why this needs discussion>
- **Options**:
  - (a) <option 1> — pros / cons
  - (b) <option 2> — pros / cons
- **Recommendation**: <if any>
```

## Output (response format)

### Per-Issue report

For each Issue:

- **Issue**: `#<N>` — `<title>`
- **Checklist**: pass/fail per criterion (compact table)
- **Findings**: list of defects with severity
- **Status**: Clean / Needs fix (Category A) / Needs discussion (Category B)

### Cross-Issue report

- **Dependency graph**: visual or table
- **Interface contracts**: agreements / conflicts
- **Shared logic**: identified extractions
- **Parallel opportunities**: which Issues can run concurrently

### Action summary

- **Category A fixes applied**: count + list
- **Category B discussion points**: count + list
- **Overall readiness**: ready to implement / blocked on discussion

## Constraints

- Do NOT create or close Issues. Only edit existing Issue bodies.
- Do NOT modify code. This is a planning/review command.
- Preserve the original author's intent when editing Issue bodies — add or clarify, don't rewrite.
- When editing, add a `## Revision History` section at the bottom noting what was changed and when.
- If an Issue body is too large for `gh issue edit`, split the edit into sections.

## Related

- `@.cursor/commands/issue-create.md` (Issue creation standards)
- `@.cursor/commands/implement.md` (consumes Issues)
- `@.cursor/commands/next.md` (orchestrator that may invoke this)
- `@.cursor/rules/workflow-policy.mdc` (Issue-driven workflow)
- `@.cursor/rules/test-strategy.mdc` (test plan quality standards)
