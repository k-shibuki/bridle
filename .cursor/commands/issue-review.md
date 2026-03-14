# issue-review

## Reads
- `workflow--issue-quality-checklist.md` (12-item per-Issue checklist, 6-item cross-Issue analysis, finding classification)
- `test-strategy.mdc` (test plan quality standards)

## Sense

1. `make evidence-issue` for all open Issues (or `make evidence-issue ISSUE=<N>` for scoped review).
2. Read relevant ADRs (`docs/adr/`), schemas (`docs/schemas/`), existing R source and tests.

## Act

1. Evaluate each Issue against the 12-item per-Issue checklist in `workflow--issue-quality-checklist.md`.
2. Run the 6-item cross-Issue analysis for the full set.
3. Classify findings: Category A (fix immediately via `gh issue edit`) or Category B (present for discussion).
4. Apply Category A fixes. Present Category B as numbered discussion points with options.

## Output

### Per-Issue
- Issue: `#<N>` — title
- Checklist: pass/fail per criterion
- Status: Clean / Needs fix (Cat A) / Needs discussion (Cat B)

### Cross-Issue
- Dependency graph
- Interface contracts (agreements / conflicts)
- Parallel opportunities

### Action summary
- Category A fixes applied: count
- Category B discussion points: count
- Overall readiness: ready / blocked

## Guard
- Do NOT create or close Issues (only edit existing bodies)
- Do NOT modify R source code
- Preserve original author's intent when editing
