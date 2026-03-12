---
trigger: issue selection, issue prioritization, next issue, actionable issue, blocked issue, dependency graph ranking, issue auto-select
---
# Issue Selection Algorithm

Declarative rules for selecting the next Issue to implement.
Extracted from `implement.md` Step 0 and `next.md` issue evaluation.
These are selection criteria (facts), not execution commands.

## Actionability Filter

An Issue is **actionable** when ALL conditions hold:

| Condition | Check | Evidence source |
|-----------|-------|-----------------|
| Not blocked | All `blocked_by` Issues are closed | `evidence-issue.issues[].blocked_by` |
| Not a parent | No open sub-issues remain | `evidence-issue.issues[].is_parent` |
| Not assigned to others | `assignee` is null or self | `evidence-issue.issues[].assignee` |
| Has required fields | `has_test_plan` AND `has_acceptance_criteria` | `evidence-issue.issues[]` |

## Ranking Criteria

Among actionable Issues, rank by (highest weight first):

| Priority | Signal | Source | Rationale |
|----------|--------|--------|-----------|
| 1st | Priority label | `labels[]` contains `high` > `medium` > `low` | Explicit prioritization |
| 2nd | Unblocks most | Count of Issues in `blocks[]` | Maximize throughput |
| 3rd | Dependency depth | `evidence-issue.dependency_graph.depth` for the Issue | Shallower = fewer prereqs |
| 4th | Age | `created_at` (older = higher) | FIFO fairness |

## Dependency Graph Properties

| Property | Source | Meaning |
|----------|--------|---------|
| `roots` | `evidence-issue.dependency_graph.roots` | Issues with no blockers |
| `leaves` | `evidence-issue.dependency_graph.leaves` | Issues that block nothing |
| `depth` | `evidence-issue.dependency_graph.depth` | Max dependency chain length |

## Special Cases

- **No actionable Issues**: Transition to ST_NO_WORK; suggest `issue-create`
- **All Issues blocked**: Report the blocking graph; suggest resolving blockers
- **Parent Issues**: Never selected directly; select their unblocked children
- **Exception flow**: Hotfix/no-issue Issues bypass normal selection

## Related

- `implement.md` Step 0 — procedural selection steps
- `controls--workflow-state-machine.md` — ST_READY and ST_NO_WORK states
- `evidence-issue` — evidence target for Issue metadata
