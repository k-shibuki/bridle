---
trigger: issue quality checklist, per-issue check, cross-issue analysis, issue review criteria, preflight review
---
# Issue Quality Checklist

Quality criteria for reviewing existing GitHub Issues before implementation.
Used by the `issue-review` action card during the PreFlightReview state.

## Per-Issue Checklist (12 items)

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
| 11 | **Scope** | Child Issue is implementable in 1 PR, OR parent Issue is explicitly structured as an Epic with linked child Issues | Warning |
| 12 | **Title convention** | Follows `<type>: <description>` format | Warning |

## Cross-Issue Analysis (6 items)

Beyond per-Issue checks, evaluate the Issue set as a whole:

| # | Category | Check |
|---|----------|-------|
| 1 | **Dependency graph** | No circular dependencies; dependency order is achievable |
| 2 | **Interface contracts** | Issues that produce/consume shared data structures agree on types |
| 3 | **Shared logic** | Common logic needed by multiple Issues is identified (not duplicated) |
| 4 | **Coverage gaps** | No important component is missing an Issue |
| 5 | **Parallel opportunities** | Independent Issues that can be worked on simultaneously are identified |
| 6 | **helper-mocks.R plan** | Mock functions needed across Issues are identified |

## Finding Classification

Split findings into two categories:

- **Category A (fix immediately)**: Missing/incorrect headings, stale dependency
  references, vague test plan entries, missing mock strategy, title convention
  fixes, missing file predictions. Apply via `gh issue edit`.
- **Category B (discussion required)**: Interface contract disagreements, scope
  concerns (including missing/unclear Epic decomposition), ADR gaps, shared logic extraction, technology choices. Present as
  numbered discussion points with context and options.

## Related

- `workflow-policy.mdc` § Issue-Driven Workflow
- `issue-create.md` — Issue creation standards (Test Plan Guidelines)
- `test-strategy.mdc` — test plan quality standards
