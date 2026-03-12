# pr-create

## Purpose

Create a pull request on GitHub that closes the tracking Issue.

## Inputs (ask if missing)

- **Issue number** (required unless exception)
- If no Issue: user must confirm exception type (`hotfix` or `no-issue`)

## Sense

Run `make evidence-workflow-position` or quick-check:
- `git branch --show-current` — must be on feature branch (not `main`)
- `git status --short` — must have no uncommitted changes (or commit first)

## Orient

### Branch and base policy

- Feature branches: `<prefix>/<issue-number>-<short-description>` per `commit-format.mdc`
- **Always target `main`** (`HS-PR-BASE`) — never use `--base feat/<branch>`
- Document dependencies in PR body, not through base branch

### PR body template

Read `.github/PULL_REQUEST_TEMPLATE.md` (SSOT) before every PR creation (`HS-PR-TEMPLATE`). Required sections:

| Section | Required? |
|---------|-----------|
| `## Summary` | Always |
| `## Traceability` | Always (`Closes #N` or Exception block) |
| `## Risk / Impact` | Always |
| `## Rollback Plan` | Non-docs/test |

### Standard vs Exception path

- **Standard**: PR body includes `Closes #<issue>`. Delete `## Exception` section.
- **Exception** (hotfix/no-issue): Add exception label, fill `## Exception` section with Type + Justification (min 20 chars).

### FSM context

This command runs in state **Committed**. Valid transitions: → CIPending (PR created, CI starts).

## Act

### 1. Ensure feature branch

If on `main`, create branch per `commit-format.mdc` § Branch Naming.

### 2. Commit if needed

Follow `commit-format.mdc`. Include `Refs: #<issue>` in footer.

### 3. Local verification and push

The `pre-push` hook runs differential checks automatically (`HS-LOCAL-VERIFY`).

```bash
git push -u origin HEAD
```

### 4. Create PR

```bash
gh pr create --title "<type>(<scope>): <description>" \
  --label "<type>" \
  --body "<body from PULL_REQUEST_TEMPLATE.md>"
```

For exceptions, add `--label "<no-issue|hotfix>"`.

### 5. Trigger bot review and delegate monitoring

#### 5a. CodeRabbit (always)

```bash
gh pr comment <PR> --body "@coderabbitai review"
```

#### 5b. Codex (user instruction only)

Only when user explicitly requests: `gh pr comment <PR> --body "@codex review"`

#### 5c. Delegate CI + review wait

Delegate to background subagent using `.cursor/templates/delegation--review-wait.md` (Monitor CI: YES). See `agent--delegation-decision.md` for the decision flowchart.

**Auto-merge guard**: MUST NOT set auto-merge until bot review completes (per `controls--merge-invariants.md`).

### 6. CI failure handling

Per `coding-policy.mdc` § CI Failure Autonomy: diagnose, fix, re-push. See `ci--failure-triage.md` for classification. For `check-policy` failures, update the PR body:

```bash
gh pr edit <N> --body "<corrected body>"
```

## Guard / Validation

- `HS-PR-BASE`: all PRs target `main`
- `HS-PR-TEMPLATE`: all required sections present
- `HS-LOCAL-VERIFY`: pre-push hook runs before every push
- `check-policy` CI job: validates PR body structure

> **Observation gap**: All external state is acquired via `make` evidence targets. If information is not available from any target, report it as a missing evidence target.

> **Anti-pattern — judgment creep**: PR body structure is defined in the template. Branch policy is in `commit-format.mdc`. This procedure assembles them — it does not redefine them.

## Related

- `.github/PULL_REQUEST_TEMPLATE.md` — PR body SSOT
- `commit-format.mdc` — commit + branch naming
- `controls--merge-invariants.md` — auto-merge guard
- `agent--delegation-decision.md` — delegation flowchart
- `ci--failure-triage.md` — CI failure classification
