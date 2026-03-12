---
trigger: gh pr edit, GraphQL Projects Classic, gh api PATCH, pr body update, gh cli workaround
---
# gh CLI Workarounds

Known issues with the `gh` CLI and their workarounds. This atom captures
operational gotchas — not policy decisions — per `architecture.md` §
Knowledge component.

## `gh pr edit --body` fails with GraphQL Projects Classic error

**Symptom**: `gh pr edit <N> --body "..."` fails with:

```
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

To update a section within an existing body:

```bash
CURRENT_BODY=$(gh pr view <N> --json body --jq '.body')
NEW_BODY=$(echo "$CURRENT_BODY" | sed 's|<placeholder>|<replacement>|')
gh api "repos/{owner}/{repo}/pulls/<N>" \
  -X PATCH \
  -f body="$NEW_BODY" \
  --jq '.html_url'
```

**Note**: `gh pr view --json body` (read) still works — only the edit
mutation is affected.

## Related

- `controls--observation-execution-boundary.md` — `gh pr edit` is an
  execution command (raw CLI permitted)
- `pr-merge.md` § Step 2 — uses `gh pr edit` for CI evidence recording
