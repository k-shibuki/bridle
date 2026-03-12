---
trigger: gh pr edit, GraphQL Projects Classic, gh api PATCH, pr body update, gh cli workaround
---
# gh CLI Workarounds

Known issues with the `gh` CLI and their workarounds. This atom captures
operational gotchas — not policy decisions — per `architecture.md` §
Knowledge component.

## `gh pr edit --body` fails with GraphQL Projects Classic error

**Symptom**: `gh pr edit <N> --body "..."` fails with:

```text
GraphQL: Projects (classic) is being deprecated (...)
```

**Root cause**: `gh pr edit` uses a GraphQL mutation that touches the
Projects Classic API, which GitHub is deprecating. The error fires even
when the repository has no classic projects.

**Affected versions**: `gh` CLI 2.40+ (observed from 2025-Q4 onward).

**Workaround**: Use the REST API `PATCH` endpoint directly:

```bash
gh api "repos/{owner}/{repo}/pulls/<N>" \
  -X PATCH \
  -f body="<new body>" \
  --jq '.html_url'
```

To update a section within an existing body, supply the current body
from agent context or evidence (preferred), or fetch inline as part of
the execution sequence:

```bash
CURRENT_BODY=$(gh pr view <N> --json body --jq '.body')
NEW_BODY=$(echo "$CURRENT_BODY" | sed 's|<placeholder>|<replacement>|')
gh api "repos/{owner}/{repo}/pulls/<N>" \
  -X PATCH \
  -f body="$NEW_BODY" \
  --jq '.html_url'
```

**HS-EVIDENCE-FIRST caveat**: The `gh pr view` read above is a raw CLI
observation. In agent Procedures, prefer sourcing the current body from
existing evidence (`make evidence-pull-request` does not yet include
the full PR body). When no evidence field exists, the inline read is
tolerated as a necessary input to the PATCH mutation — not standalone
observation.

## Related

- `controls--observation-execution-boundary.md` — `gh pr edit` is an
  execution command (raw CLI permitted)
- `pr-merge.md` § Step 2 — uses `gh pr edit` for CI evidence recording
