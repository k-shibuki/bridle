---
trigger: merge strategy selection, squash vs merge, high-risk merge, merge strategy table
---
# Merge Strategy Selection

How to choose between squash and merge strategies, and when to apply
extra caution for high-risk changes. Merge preconditions are in
`controls--merge-invariants.md`; this atom covers the strategy decision.

## Strategy Selection

| Source | Commit pattern | Strategy |
|--------|---------------|----------|
| AI agent | Many micro-commits from iterative development | **squash** |
| Human | 2-5 meaningful, logically structured commits | merge |

Default for AI-driven PRs is **squash** — the individual commits are
implementation artifacts, not a meaningful history.

## High-Risk Change Policy

Changes to the following areas require extra caution before merging.
Confirm with the user before executing merge:

- **Schemas** (`docs/schemas/`): data contracts affect all consumers
- **CI pipeline** (`.github/workflows/`): broken CI blocks all PRs
- **AI rules** (`.cursor/rules/`, `.cursor/commands/`): affects agent behavior
- **Security**: authentication, authorization, network boundaries

## Related

- `controls--merge-invariants.md` — 5 mandatory merge preconditions
- `agent-safety.mdc` § HS-CI-MERGE — Hard Stop definition
- `pr-merge` action card — merge execution procedure
