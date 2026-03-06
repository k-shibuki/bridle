---
name: Feature Request
about: Propose a new feature or enhancement
title: "feat: "
labels: enhancement
---

## Summary

<!-- 1-2 sentences describing the feature. -->

## Motivation

<!-- Why is this needed? What problem does it solve? -->

## Related ADR

<!-- Which ADR(s) govern this feature? If none, should a new ADR be created? -->

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

<!-- Concrete, verifiable criteria. The PR reviewer will check these. -->

- [ ]
- [ ]

## Test Plan

<!--
Include CONCRETE test cases with specific input values and expected outputs.
The Issue should be self-contained — a reader can understand what to test without other docs.

Requirements:
- At least 2 normal cases with distinct, concrete inputs
- At least 2 error/validation cases (NULL, type mismatch, constraint violation, etc.)
- At least 1 boundary case where applicable (empty, single element, max, etc.)

Anti-patterns (DO NOT use):
- "valid input" / "invalid input" without specifics
- "succeeds" / "fails" without describing the outcome
-->

| Scenario | Input / Precondition | Expected Result | Notes |
|----------|---------------------|-----------------|-------|
| <!-- e.g., Valid 3-node graph --> | <!-- e.g., nodes=list("A","B","C"), edges=list(c("A","B"),c("B","C")) --> | <!-- e.g., DecisionGraph with 3 nodes, 2 edges, is_dag=TRUE --> | |
| <!-- e.g., Single node, no edges --> | <!-- e.g., nodes=list("A"), edges=list() --> | <!-- e.g., DecisionGraph with 1 node, 0 edges --> | Boundary |
| <!-- e.g., NULL nodes --> | <!-- e.g., nodes=NULL --> | <!-- e.g., Validation error: 'nodes must not be NULL' --> | |
| <!-- e.g., Duplicate node names --> | <!-- e.g., nodes=list("A","A") --> | <!-- e.g., Validation error: 'node names must be unique' --> | |

## Sub-issues

<!-- For large tasks, list child Issues here after decomposition. -->

<!-- - [ ] #child-issue-1 -->
<!-- - [ ] #child-issue-2 -->

## Priority / Affected Area

- Priority: <!-- high / medium / low -->
- Affected area: <!-- e.g., R/, docs/schemas/, tests/ -->
