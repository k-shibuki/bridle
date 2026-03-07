# implement

## Purpose

Select and implement the next task from open GitHub Issues (code changes only; no tests in this step).

When an Issue number is provided, implement that specific Issue.
When no Issue number is provided, analyze open Issues to find the best candidate, present the selection rationale, and proceed after user approval.

## When to use

- After creating Issues with `issue-create` and agreeing on an implementation plan
- Any time you need to implement a scoped change that is already tracked by an Issue
- When the user wants the AI to autonomously pick the next task to work on

## Inputs

- **Issue number** (optional): the GitHub Issue to implement (e.g., `#42`). If omitted, the command auto-selects from open Issues.
- Any context documents the user wants to provide (requirements, specs, plans, etc.)
- Any relevant source files (`@R/...`) if the user already knows them

**Note**: Specific document attachments are optional. This command will actively search the codebase for necessary context.

## Constraints

- Use repo search tools (e.g., `grep`, semantic search) to find necessary context rather than guessing or asking the user for every file.
- All implementation work must be traceable to the Issue. If the scope drifts, update the Issue or create a new one.

## Steps

### Step 0: Issue selection (when no Issue number provided)

If the user did not specify an Issue number, auto-select one:

1. **Fetch open Issues**:
   ```bash
   gh issue list --state open --json number,title,labels,body --limit 50
   ```

2. **Build dependency graph**: For each Issue, extract `Depends on: #N` / `Parent: #N` references from the body. An Issue is **blocked** if any dependency is still open.

3. **Filter to actionable Issues**: Keep only Issues that are:
   - Not blocked (all dependencies are closed or absent)
   - Not a parent/umbrella Issue (has `## Sub-issues` with unclosed children)
   - Not assigned to someone else (if assignee field is used)

4. **Rank candidates** by:
   | Signal | Weight | Source |
   |--------|--------|--------|
   | Priority label (`high` > `medium` > `low`) | 1st | Issue labels |
   | Dependency depth (fewer remaining dependents = higher) | 2nd | Dependency graph |
   | Issue age (older = higher) | 3rd | Issue creation date |

5. **Present selection to user** with rationale:
   ```
   ## Issue Selection

   ### Recommended: #<N> — <title>
   - Reason: <why this is the best next task>
   - Blocked by: none
   - Enables: #<M>, #<K> (unblocks these after completion)

   ### Other candidates:
   - #<X> — <title> (reason not selected: ...)
   - #<Y> — <title> (reason not selected: ...)

   Proceed with #<N>?
   ```

6. **Wait for user approval** before proceeding. If the user picks a different Issue, use that one instead.

### Step 1: Retrieve the Issue specification

```bash
gh issue view <issue-number>
```
Extract: summary, acceptance criteria (DoD), test plan, schema impact, and related ADRs.

### Step 2: Confirm scope

Based on:
- The Issue's acceptance criteria
- Attached documents (if any)
- User instructions

### Step 3: Discover context

Actively search the codebase to understand:
- Existing code paths and patterns
- Related modules and dependencies
- Coding conventions used in the project

Also run **docs-discover (Mode 1)**: identify which docs are relevant to the upcoming change. This early discovery avoids "code changed but docs didn't" at commit time.

### Step 4: Design integration (if needed)

If the change touches interfaces/contracts across modules (APIs, schemas, request/response shapes, new parameters that must propagate), consider switching to `NEXT_COMMAND: /integration-design` to design and verify the flow.

### Step 5: Verify environment

Quick check: `make status` (shows git branch + container state in one command).
Full check: `make doctor`. If the container is not running, start it with `make container-up`.

To create a feature branch for the Issue:
```bash
make new-branch PREFIX=feat ISSUE=<number> DESC=<short-description>
```

### Step 6: Implement

1. Identify the minimal set of files to change.
2. Implement the change.
3. Do a quick sanity check (basic execution path review; avoid long-running processes unless requested).

## Output (response format)

- **Issue**: `#<number>` — title (with selection rationale if auto-selected)
- **Scope recap**: what changed (1-3 bullets)
- **Files changed**: list of paths
- **DoD progress**: which acceptance criteria are now met
- **Docs impact**: docs candidates identified via docs-discover (Mode 1)
- **Context discovered**: key files/patterns found via search (if relevant)
- **Notes**: any trade-offs, follow-ups, or risks

## Related

- `@.cursor/commands/issue-create.md` (previous step)
- `@.cursor/commands/test-create.md` (next step)
- `@.cursor/commands/docs-discover.md` (Mode 1 during Step 3, Mode 2 before commit)
- `@.cursor/rules/workflow-policy.mdc`
- `@.cursor/rules/integration-strategy.mdc` (when changes span module boundaries / contracts)
