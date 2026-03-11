---
trigger: consensus protocol, bot agreement, disposition reply, review thread resolve, unilateral resolve, comment response, review reply template, resolve thread, Fixed By design False positive Acknowledged, completeness invariant, unresolved thread, HS-REVIEW-RESOLVE, review comment reply, reply format
---
# Review Consensus Protocol

Bidirectional agreement model for review threads. All commands that
interact with review threads (`review-fix`, `pr-review`, `pr-merge`,
`next`) reference this atom as the SSOT for disposition and resolution.

## Principle

> Reach agreement with bot reviewers on ALL findings before proceeding
> to merge. Findings without agreement remain unresolved and block merge.

**Unilateral resolve is prohibited.** The agent must not resolve a thread
until the reviewer's final response confirms the disposition.

## Completeness Invariant

```
unresolved threads == 0  ⟺  all review findings have consensus
```

GitHub Branch Protection (`required_conversation_resolution`) blocks
merge until every thread is resolved. This is a Deterministic guard.

## Disposition Categories (4, exhaustive)

Every thread receives exactly one disposition reply (per `HS-REVIEW-RESOLVE`).

| Category | When | Consensus requirement | Template |
|---|---|---|---|
| **Fixed** | Code change addresses the finding | Re-review confirms fix (no new finding on same lines) | `Fixed in \`<sha7>\`. <what changed>.` |
| **By design** | Intentional design decision | Bot reply does not object (acceptance or no further comment after re-review) | `By design. <rationale> (ref: <source>).` |
| **False positive** | Bot misidentified an issue | Bot reply does not object | `False positive. <why detection was wrong>.` |
| **Acknowledged** | Valid but out of PR scope | Tracking Issue created; bot notified | `Acknowledged. <brief assessment>. Tracked in #<issue>.` |

**Acknowledged invariant**: The tracking target (`#<issue>`) MUST differ
from the Issue the PR closes. If the PR `Closes #N`, then `Tracked in #N`
is prohibited — the finding would be lost on merge.

### Bot Agreement Signals

| Signal | CodeRabbit | Codex |
|---|---|---|
| **Fix confirmed** | Re-review produces no new finding on the same file+lines | Re-review produces no new finding |
| **Objection** | New comment on the same thread or new finding on same lines | New comment on the same thread |
| **Acceptance** | No further comment after re-review completes | No further comment after re-review |
| **Timeout** | 20 min without re-review completion | 20 min without re-review completion |

**Timeout fallback**: When a bot times out on re-review, the agent may
resolve with a documented justification: `<Category>. <explanation>.
Bot re-review timed out; proceeding per consensus protocol timeout fallback.`

### Consensus Flow

```text
1. Agent posts disposition reply on thread
2. Agent triggers re-review (@coderabbitai review / @codex review)
3. Wait for re-review (via delegation--review-wait.md)
4. Check result:
   ├── No new finding on thread → consensus reached → resolve thread
   ├── New finding / objection  → address finding → go to step 1
   └── Timeout                  → resolve with timeout justification
```

For copy-paste reply templates with examples, see
`templates/review--disposition-reply.md`.

## Reply API (REST)

Post a threaded reply to an inline review comment:

```bash
gh api repos/{owner}/{repo}/pulls/<N>/comments/<comment_id>/replies \
  -f body="Fixed in \`abc1234\`. Aligned timeout values to 20 min."
```

`<comment_id>` is the `databaseId` of the root comment in the thread.

## Resolve API (GraphQL)

Resolve a thread after consensus is confirmed:

```bash
gh api graphql -f query='
  mutation($id: ID!) {
    resolveReviewThread(input: {threadId: $id}) {
      thread { isResolved }
    }
  }
' -f id="<THREAD_ID>"
```

## Thread Enumeration (GraphQL)

```bash
gh api graphql -f query='
  query($owner: String!, $repo: String!, $pr: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $pr) {
        reviewThreads(first: 100) {
          totalCount
          nodes {
            id
            isResolved
            isOutdated
            comments(first: 1) {
              nodes {
                id: databaseId
                author { login }
                body
              }
            }
          }
        }
      }
    }
  }
' -f owner={owner} -f repo={repo} -F pr=<N>
```

The inner `databaseId` is `<comment_id>` for the REST reply API.
The outer `id` is `<THREAD_ID>` for the GraphQL resolve API.

## Edge Cases

- **CodeRabbit `✅ Addressed in commit`**: Informational only — does NOT
  constitute consensus. Wait for re-review completion.
- **`isOutdated` threads**: Still valid; `required_conversation_resolution`
  does not distinguish outdated from current.
- **Multiple comments in one thread**: Reply once to the root comment.
- **Human-replied threads**: Agent resolves if still unresolved.

## Related

- `review--bot-operations.md` — trigger, detection, polling, timing
- `templates/review--disposition-reply.md` — copy-paste reply templates
- `agent-safety.mdc` `HS-REVIEW-RESOLVE` — Hard Stop definition
- `workflow-policy.mdc` § Review Comment Response — policy declaration
- `review-fix.md` Step 3b — procedure for reply + resolve
