# implement

## Purpose

Select and implement the next task from open GitHub Issues (code changes only; no tests in this step).

## Inputs

- **Issue number** (optional): if omitted, auto-selects from open Issues
- Context documents (optional)

## Sense

### Issue selection (when no Issue number provided)

Run `make evidence-issue` for structured Issue metadata.

Consult `workflow--issue-selection.md` for the selection algorithm:
1. **Actionability filter**: not blocked, not parent, not assigned to others, has test plan + DoD
2. **Ranking**: priority label → unblocks most → dependency depth → age

Present selection with rationale and wait for user approval.

### Issue specification

Run `make evidence-issue ISSUE=<issue-number>` for structured Issue metadata.

Extract: summary, acceptance criteria (DoD), test plan, schema impact, related ADRs.
If any required field is unavailable, report a missing evidence target.

### Environment

```bash
make status
```

If container not running: `make container-up`.

## Orient

### Scope confirmation

Based on:
- Issue acceptance criteria
- User instructions
- Attached context documents

### Context discovery

Actively search the codebase to understand:
- Existing code paths and patterns
- Related modules and dependencies
- Project conventions

Run **docs-discover (Mode 1)**: identify which docs are relevant to the upcoming change.

### Integration design (if needed)

If the change touches interfaces across modules (APIs, schemas, parameter propagation), consider `integration-design` to verify the flow. See `integration-strategy.mdc`.

### FSM context

This command runs in state **ReadyToStart**. Valid transitions: → Implementing → ImplementationDone.

## Act

### 1. Create feature branch

```bash
make new-branch PREFIX=<type> ISSUE=<number> DESC=<short-description>
```

### 2. Implement

1. Identify the minimal set of files to change
2. Implement the change
3. Quick sanity check (basic execution path review)

## Guard / Validation

- All work traceable to Issue — if scope drifts, update Issue or create new one
- `pre-push` hook validates before push (`HS-LOCAL-VERIFY`)

> **Observation gap**: All external state is acquired via `make` evidence targets. If information is not available from any target, report it as a missing evidence target.

> **Anti-pattern — judgment creep**: Issue selection rules are in `workflow--issue-selection.md`. Integration patterns are in `integration-strategy.mdc`. This procedure routes to them.

## Output

- **Issue**: `#<number>` — title (with selection rationale if auto-selected)
- **Scope recap**: what changed (1-3 bullets)
- **Files changed**: list of paths
- **DoD progress**: which acceptance criteria are now met
- **Docs impact**: candidates from docs-discover (Mode 1)

## Related

- `workflow--issue-selection.md` — selection algorithm
- `issue-create.md` — previous step
- `test-create.md` — next step
- `commit-format.mdc` — branch naming
- `integration-strategy.mdc` — cross-module design
