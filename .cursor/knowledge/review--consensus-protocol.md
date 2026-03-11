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

Every thread receives a disposition reply before being resolved (per
`HS-REVIEW-RESOLVE`). If the bot objects after the initial reply, the
agent posts a new disposition reply per round until consensus is reached.

| Category | When | Consensus requirement | Template |
|---|---|---|---|
| **Fixed** | Code change addresses the finding | Re-review confirms fix (no new finding on same lines) | `Fixed in \`<sha7>\`. <what changed>.` |
| **By design** | Intentional design decision | Bot reply does not object (acceptance or no further comment after re-review) | `By design. <rationale> (ref: <source>).` |
| **False positive** | Bot misidentified an issue | Bot reply does not object | `False positive. <why detection was wrong>.` |
| **Acknowledged** | Valid but out of PR scope | Tracking Issue created; bot notified | `Acknowledged. <brief assessment>. Tracked in #<issue>.` |

**Acknowledged invariant**: The tracking target (`#<issue>`) MUST differ
from the Issue the PR closes. If the PR `Closes #N`, then `Tracked in #N`
is prohibited — the finding would be lost on merge.

### Consensus Flow

```text
1. Post disposition reply on thread
2. Observe (collect evidence):
   a. Thread state — isResolved? (bot may auto-resolve)
   b. Thread replies — did bot confirm or object?
   c. Re-review results — new findings on same area?
3. Decide:
   ├── Bot auto-resolved thread        → consensus confirmed
   ├── Bot replied with confirmation   → resolve thread
   ├── Bot replied with objection      → address, go to 1
   ├── No response + reviewer available → trigger re-review, go to 2
   └── No response + reviewer unavailable → agent resolves (see below)
```

**Bot behavior differs** — see `review--bot-operations.md` § Agreement
Mechanics for how each bot expresses agreement.

### Reviewer Unavailable

When a reviewer cannot respond (usage limit, service outage, timeout):

- Agent resolves with justification: `<Category>. <explanation>.
  Reviewer unavailable (<reason>); fix verified by <evidence>.`
- Evidence examples: other bot confirmed, code change is mechanically
  correct, independent reviewer (Cursor) verified

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

- **CodeRabbit auto-resolve**: CR may confirm a fix and resolve the thread
  itself after reading the disposition reply. This IS consensus — no
  further action needed.
- **CodeRabbit `✅ Addressed in commit`**: Informational marker only.
  Check whether CR also replied with confirmation or auto-resolved.
- **`isOutdated` threads**: Still valid; `required_conversation_resolution`
  does not distinguish outdated from current.
- **Multiple comments in one thread**: Reply once to the root comment.
- **Human-replied threads**: Agent does not auto-resolve. Leave for
  the human reviewer to resolve, or resolve only after explicit
  acceptance from the reviewer or user instruction.

## Related

- `review--bot-operations.md` — trigger, detection, polling, timing
- `templates/review--disposition-reply.md` — copy-paste reply templates
- `agent-safety.mdc` `HS-REVIEW-RESOLVE` — Hard Stop definition
- `workflow-policy.mdc` § Review Comment Response — policy declaration
- `review-fix.md` Step 3b — procedure for reply + resolve
