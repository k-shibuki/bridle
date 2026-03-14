---
name: Task
about: Feature, refactor, chore, or any non-bug task
title: ""
labels: ""
---

## Summary

<!-- 1-2 sentences describing the task. -->

## Motivation

<!-- Why is this needed? What problem does it solve? -->

## Related ADR

<!-- Which ADR(s) govern this change? If none, should a new ADR be created? -->

- ADR:

## Schema Impact

<!-- Will this require changes to YAML schemas or S7 classes? -->

- [ ] No schema impact
- [ ] New schema needed
- [ ] Existing schema modification
- [ ] New or modified S7 class

## Proposed Approach

<!-- Optional: how would you implement this? -->

## Acceptance Criteria (Definition of Done)

<!-- Concrete, verifiable criteria. Use plain bullets (- item), not checkboxes. -->

-
-

## Test Plan

<!-- Concrete test cases with specific inputs and expected outputs.
     Min: 2 normal + 2 error + 1 boundary case. No vague placeholders.
     Full guidelines: .cursor/commands/issue-create.md § Test Plan Guidelines -->

| Scenario | Input / Precondition | Expected Result | Notes |
|----------|---------------------|-----------------|-------|
| <!-- e.g., Valid 3-node graph --> | <!-- e.g., nodes=list("A","B","C"), edges=list(c("A","B"),c("B","C")) --> | <!-- e.g., DecisionGraph with 3 nodes, 2 edges, is_dag=TRUE --> | |
| <!-- e.g., Single node, no edges --> | <!-- e.g., nodes=list("A"), edges=list() --> | <!-- e.g., DecisionGraph with 1 node, 0 edges --> | Boundary |
| <!-- e.g., NULL nodes --> | <!-- e.g., nodes=NULL --> | <!-- e.g., Validation error: 'nodes must not be NULL' --> | |
| <!-- e.g., Duplicate node names --> | <!-- e.g., nodes=list("A","A") --> | <!-- e.g., Validation error: 'node names must be unique' --> | |

## Risks / Open Questions

<!-- Anything that needs clarification, external dependencies, or potential pitfalls. -->

## Sub-issues

<!-- For large tasks, list child Issues here after decomposition. -->

<!-- - [ ] #child-issue-1 -->
<!-- - [ ] #child-issue-2 -->

## Priority / Affected Area

- Priority: <!-- high / medium / low -->
- Affected area: <!-- e.g., R/, docs/schemas/, tests/ -->
