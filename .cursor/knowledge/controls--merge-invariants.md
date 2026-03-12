---
trigger: merge invariant, merge precondition, merge readiness, pr-merge gate, CI green merge, review freshness, merge state check, auto-merge precondition, auto-merge guard, bot review pending merge, delegated merge
---
# Merge Invariants

Declarative preconditions that must hold before any PR merge.
These are facts (invariants), not execution steps. Procedural
merge steps are in `pr-merge.md`.

## Mandatory Preconditions

All 5 must be TRUE for merge to proceed:

| # | Invariant | Signal | Guard |
|---|-----------|--------|-------|
| 1 | CI is green | `ci_status == "success"` | HS-CI-MERGE |
| 2 | Review concluded mergeable | `review_concluded == true` OR user explicit merge instruction | — |
| 3 | CI evidence recorded | `## Test Evidence` section is non-empty | Audit trail |
| 4 | Branch is mergeable | `merge_state_status ∈ {"CLEAN", "HAS_HOOKS"}` | — |
| 5 | Bot review covers latest push | Bot review `submitted_at > last_push_at` OR silent clean bill | Review freshness |

## Merge State Resolution

| `mergeStateStatus` | Meaning | Action |
|--------------------|---------|--------|
| CLEAN | Ready to merge | Proceed |
| HAS_HOOKS | Hooks will run on merge | Proceed (hooks are expected) |
| BEHIND | Base branch has new commits | Update branch, re-verify CI |
| DIRTY | Merge conflict | Resolve conflict (see `git--squash-merge-dependent-branch.md`) |
| BLOCKED | Branch protection prevents merge | Diagnose which protection rule blocks |
| UNKNOWN | State not yet computed | Wait and re-check |

## Auto-Merge Decision

| Condition | Auto-merge | Delegated merge |
|-----------|:----------:|:---------------:|
| Single PR, all preconditions met | ✓ | — |
| Dependent PR chain (ordered) | — | ✓ |
| Bot review still pending | **PROHIBITED** | — |
| Token lacks auto-merge permission | — | ✓ (fallback) |

**Auto-merge guard**: MUST NOT set auto-merge while bot review is
pending. Rationale: `required_conversation_resolution` only blocks
when unresolved threads exist. No review = zero threads = protection
vacuously passes — the PR would merge without any review.

## Related

- `pr-merge.md` — procedural merge steps
- `controls--workflow-state-machine.md` — FSM guard conditions
- `agent--delegation-decision.md` — delegation flowchart
- `agent-safety.mdc` § HS-CI-MERGE
