# Template: Review Disposition Reply

Every review thread must receive exactly one disposition reply before being
resolved (per `agent-safety.mdc` `HS-REVIEW-RESOLVE`).

## Reply Templates

**Fixed** — evidence: commit SHA, explanation: what was changed
```
Fixed in `<sha7>`. <what changed>.
```

Example:
```
Fixed in `f561c8d`. Aligned timeout values to 20 min across all sections.
```

**By design** — evidence: reference (ADR/rule/command), explanation: design rationale
```
By design. <rationale> (ref: <source>).
```

Example:
```
By design. Step 5 auto-loops after initial consent; HS-NO-SKIP ensures
intra-command steps are still followed (ref: next.md § Approval scope).
```

**False positive** — no evidence (the detection itself was wrong), explanation: why
```
False positive. <why detection was wrong>.
```

Example:
```
False positive. The cross-reference formats differ intentionally —
parenthetical vs dash style matches surrounding sentence structure.
```

**Acknowledged** — evidence: tracking issue, explanation: assessment result
```
Acknowledged. <brief assessment>. Tracked in #<issue>.
```

Example:
```
Acknowledged. Valid observation; container bootstrap step would improve
usability. Out of scope for SSOT cleanup. Tracked in #201.
```

## API Commands

### Post reply to a thread

Use the full-parameter `POST /pulls/{N}/comments` form with `in_reply_to`.
Do **not** use the `/pulls/comments/{id}/replies` shortcut — it returns
404 for recently created review comments.

```bash
gh api repos/{owner}/{repo}/pulls/{N}/comments -X POST \
  -f body='<disposition text>' \
  -F in_reply_to=<database_id> \
  -f commit_id=<full_sha> \
  -f path=<file_path> \
  -F line=<line_number>
```

- `database_id`: root comment's `databaseId` from `make evidence-review-threads`
- `commit_id`: full 40-char SHA of HEAD (required; short SHA causes 422)
- `path`, `line`: from the thread's root comment

### Resolve a thread (after consensus)

```bash
gh api graphql -f query='
  mutation { resolveReviewThread(input: {threadId: "<graphql_id>"}) {
    thread { isResolved }
  }
}'
```

- `graphql_id`: thread's `graphql_id` from `make evidence-review-threads`
- Only resolve after bot confirms disposition (auto-resolve or explicit reply)

### Enumerate unresolved threads

```bash
make evidence-review-threads PR=<N>
```

Output includes per-thread: `graphql_id`, `database_id`, `path`, `line`,
`body`, `is_resolved`, `is_outdated`, and `replies`.

## Design Principles

- **Category keyword first**: grep `^Fixed`, `^By design`, `^False positive`, `^Acknowledged` for machine classification
- **Evidence is minimal and verifiable**: SHA via git, Issue # via GitHub, ref via codebase
- **Explanation is 1-2 sentences**: auditor can understand disposition without opening the thread
- **English**: consistent with code and commit language
