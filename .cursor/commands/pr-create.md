# pr-create

## Reads
- `workflow-policy.mdc` § Exception Policy (standard vs exception path)
- `.github/PULL_REQUEST_TEMPLATE.md` (PR body SSOT — read before every PR creation per `HS-PR-TEMPLATE`)
- `commit-format.mdc` § Branch Naming Convention
- `review--bot-operations.md` § CR Review Budget
- `subagent-policy.mdc` (delegation for CI + review wait)
- `agent--delegation-decision.md` (template selection)

## Sense

`make evidence-workflow-position` — verify on feature branch with no uncommitted files.

## Act

1. Push: `git push -u origin HEAD` (pre-push hook runs per `HS-LOCAL-VERIFY`).
2. Create PR: `gh pr create --title "<type>(<scope>): <desc>" --base "main" --label "<type>" --body "<from template>"`. For exceptions: add `--label "<no-issue|hotfix>"`.
3. Trigger CodeRabbit: `gh pr comment <PR> --body "@coderabbitai review"`. Codex only on user instruction.
4. Delegate CI + review wait via `delegation--review-wait.md` (Monitor CI: YES). MUST NOT set auto-merge while bot review is pending.
5. On `check-policy` failure: `gh pr edit <N> --body "<corrected body>"`.

## Output
- PR URL and number
- CI status at delegation time
- Bot review trigger confirmation

## Guard
- `HS-PR-BASE`: all PRs target `main`
- `HS-PR-TEMPLATE`: all required sections present
- `HS-LOCAL-VERIFY`: pre-push hook runs
- `HS-CI-MERGE`: auto-merge guard (no auto-merge while bot review pending)
