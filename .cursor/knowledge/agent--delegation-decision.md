---
trigger: CI-wait template, CI-wait only, merge template, batch auto-merge, dependent PR merge, delegation template, subagent prompt template, background subagent, Codex wait, CI Codex wait
---
# Subagent Delegation Decision

Three-branch decision for selecting the correct delegation template.
Templates live in `.cursor/templates/delegation--*.md`.

## Decision Flowchart

```text
What is blocking?
├── Bot review pending ──→ delegation--review-wait.md (Monitor CI = YES/NO)
├── Dependent chain ──→ delegation--dependent-chain.md
└── CI only ──→ delegation--ci-wait-only.md
                └── Ready to merge? → gh pr merge --auto --squash (preferred)
```

**Primary path**: After `pr-review` concludes "Mergeable", use
`gh pr merge --auto --squash` (Deterministic — GitHub enforces checks).
Templates are for monitoring or multi-PR coordination.

**Auto-merge guard**: MUST NOT set auto-merge while bot review is pending.
No review → no threads → `required_conversation_resolution` does not
block → CI green alone triggers merge. See `review--consensus-protocol.md`.

## Batch Auto-Merge (multiple independent PRs)

```bash
gh pr merge <A> --auto --squash
gh pr merge <B> --auto --squash
```

GitHub merges each independently as CI passes.

## Templates

| Template | When to use |
|---|---|
| `delegation--review-wait.md` | Bot review pending (with optional CI monitoring) |
| `delegation--ci-wait-only.md` | CI monitoring only (no merge, no review) |
| `delegation--dependent-chain.md` | Dependent PRs needing sequential merge + rebase |
