# implement

## Reads

- `workflow--issue-selection.md` (selection algorithm when no Issue provided)
- `workflow--docs-discovery-heuristics.md` (early doc impact identification)
- `integration-strategy.mdc` (if change touches cross-module interfaces)

## Sense

1. If no Issue number provided: `make evidence-issue` for selection per `workflow--issue-selection.md`. Present selection with rationale and wait for approval.
2. `make evidence-issue ISSUE=<N>` for structured Issue metadata (summary, DoD, test plan, schema impact, related ADRs).
3. `make status` — if container not running: `make container-start`.

## Act

1. Create feature branch: `make git-new-branch PREFIX=<type> ISSUE=<number> DESC=<short-description>`
2. Search codebase to understand existing code paths, patterns, and dependencies.
3. **Doc discovery (Mode 1)**: Identify candidate docs affected by the upcoming change using `workflow--docs-discovery-heuristics.md`. Output a doc impact list that carries forward to `commit`.
4. If cross-module: consider `integration-design` to verify flow.
5. Implement the change (minimal file set, code only — no tests in this step).

## Output

- Issue: `#<number>` — title (with selection rationale if auto-selected)
- Scope recap: what changed (1-3 bullets)
- Files changed: list of paths
- DoD progress: which acceptance criteria are met
- Doc impact list: candidates from step 3

## Guard

- All work traceable to Issue
- `HS-LOCAL-VERIFY`: pre-push hook validates before push
- `HS-EVIDENCE-FIRST`: observation via `make evidence-*` only
