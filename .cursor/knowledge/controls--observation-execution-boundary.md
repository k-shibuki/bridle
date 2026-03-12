---
trigger: observation execution boundary, evidence-first, raw CLI, observation command, execution command, delegated process, HS-EVIDENCE-FIRST, ad-hoc observation, make evidence
---
# Observation–Execution Boundary

Classification of agent commands into three categories. This atom is
the SSOT for `HS-EVIDENCE-FIRST` — it defines which commands are
observation (prohibited as raw CLI) and which are execution (permitted).

## Three Categories

### 1. Observation (MUST use evidence targets)

Commands that **read** external state. Prohibited as raw CLI in the
main agent per `HS-EVIDENCE-FIRST`.

| What | Raw CLI (prohibited) | Evidence target |
|---|---|---|
| Git state | `git status`, `git branch`, `git log` | `make evidence-workflow-position` |
| Open Issues | `gh issue list`, `gh issue view` | `make evidence-issue ISSUE=N` |
| Open PRs (routing) | `gh pr list`, `gh pr view`, `gh pr checks` | `make evidence-workflow-position` or `make evidence-pull-request PR=N` |
| PR detail (CI, merge, reviews) | `gh api .../pulls/N/reviews` | `make evidence-pull-request PR=N` |
| Review threads (per-thread) | `gh api graphql ...reviewThreads` | `make evidence-review-threads PR=N` |
| Environment health | manual doctor checks | `make evidence-environment` |
| Lint results | `lintr::lint_package()` direct | `make evidence-lint` |

### 2. Execution (raw CLI permitted)

Commands that **change** external state. These are mutations and are
used directly in Procedure Act sections.

| Category | Examples |
|---|---|
| Git mutations | `git commit`, `git push`, `git checkout`, `git rebase` |
| PR lifecycle | `gh pr create`, `gh pr merge`, `gh pr edit`, `gh pr comment` |
| Review actions | `gh api .../comments/{id}/replies` (disposition reply), `gh api graphql ...resolveReviewThread` |
| Issue mutations | `gh issue create`, `gh issue close`, `gh issue edit` |
| Build/test | `make format-check`, `make test`, `devtools::check()` |

### 3. Delegated process (raw CLI in subagent only)

Commands used within subagent delegation templates for polling loops.
Prohibited in the main agent per `HS-NO-INLINE-POLL`; permitted inside
`delegation--*.md` templates executed by background subagents.

| Category | Examples |
|---|---|
| CI polling | `gh pr checks <N>` (in `delegation--ci-wait-only.md`) |
| Review polling | `gh api .../pulls/N/reviews`, `gh api .../issues/N/comments` (in `delegation--review-wait.md`) |
| Sleep cycles | `sleep 20`, `sleep 30` (in delegation templates only) |

## Decision Rule

```
Is the command reading state or changing state?
├── Reading → Use `make evidence-*` target (HS-EVIDENCE-FIRST)
│   └── No target exists? → Report missing evidence target
└── Changing → Use raw CLI directly
    └── Involves waiting > 10s? → Delegate to subagent (HS-NO-INLINE-POLL)
```

## Related

- `agent-safety.mdc` `HS-EVIDENCE-FIRST` — prohibition definition
- `agent-safety.mdc` `HS-NO-INLINE-POLL` — delegation prohibition
- `subagent-policy.mdc` — delegation process details
- `docs/agent-control/evidence-schema.md` — evidence target schemas
