---
trigger: CI-wait template, CI-wait only, merge template, batch auto-merge, dependent PR merge, delegation template, subagent prompt template, background subagent, Codex wait, CI Codex wait
---
# Subagent Delegation Decision

Decision flowchart and batch strategy for selecting the correct delegation
template. Individual templates live in `.cursor/templates/delegation--*.md`.

## Decision Flowchart

Before choosing a template, follow this decision tree:

```text
Bot review triggered?
├── Yes + CI also pending ──→ delegation--ci-bot-review-wait.md
├── Yes + CI already passed ──→ delegation--bot-review-wait.md
└── No
    └── Bot review completed? (*)
        ├── No (review pending) ──→ WAIT — do NOT set auto-merge (see pr-create.md § 5d)
        └── Yes (or not triggered)
            └── PR ready to merge? (**)
                ├── No (CI monitoring only) ──→ delegation--ci-wait-only.md
                └── Yes
                    ├── Single PR?
                    │   ├── Yes ──→ `gh pr merge --auto --squash` (preferred, Deterministic)
                    │   │          └── Auto-merge failed? ──→ delegation--ci-wait-merge.md (Fallback)
                    │   └── No (multiple PRs)
                    │       ├── Independent PRs ──→ Batch Auto-Merge (below)
                    │       └── Dependent PRs (shared commits) ──→ delegation--dependent-chain.md

(*) Bot review completed = monitoring subagent reported REVIEWED / CLEAN / TIMED_OUT.
    Setting auto-merge while review is pending causes review-less merges
    (no review → no threads → conversation resolution does not block).

(**) PR ready to merge = all of:
    - pr-review concluded "Mergeable" on current HEAD
    - No unresolved review threads
    - No re-review pending (no push since last completed review)
```

**Primary path**: For single PRs after `pr-review`, use `gh pr merge --auto --squash`
(see `pr-merge.md` § Auto-merge). This moves merge execution from Steering (agent
polls and merges) to Deterministic (GitHub enforces required checks and merges
automatically). Templates are for fallback or multi-PR coordination only.

## Batch Auto-Merge (multiple independent PRs)

For multiple independent PRs that all have `pr-review` completed, set auto-merge
on each PR individually. No subagent delegation is needed:

```bash
gh pr merge <A> --auto --squash
gh pr merge <B> --auto --squash
gh pr merge <C> --auto --squash
```

GitHub merges each PR independently as its CI passes. If auto-merge fails on
any PR, fall back to `delegation--ci-wait-merge.md` for that specific PR.

## Templates

| Template file | When to use |
|---|---|
| `delegation--ci-wait-merge.md` | Single PR, auto-merge failed, pr-review done |
| `delegation--ci-wait-only.md` | CI monitoring only (no merge intent) |
| `delegation--dependent-chain.md` | Dependent PRs with shared commits |
| `delegation--ci-bot-review-wait.md` | CI + bot review both pending |
| `delegation--bot-review-wait.md` | Bot review pending, CI done or separate |

All template files are in `.cursor/templates/`.
