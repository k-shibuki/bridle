---
trigger: review comment reply, review reply template, resolve thread, disposition reply, comment response, review thread resolve, reply format, Fixed By design False positive Acknowledged, completeness invariant, unresolved thread, HS-REVIEW-RESOLVE
---
# Review Comment Response

Reply format, resolve procedure, and completeness invariant for review
threads. All commands that respond to review comments (`review-fix`,
`pr-review`, `pr-merge`, `next`) reference this atom.

For bot review lifecycle mechanics, see `review--bot-trigger.md` (trigger),
`review--bot-detection.md` (detection, polling, state machine),
`review--bot-timing.md` (timing, rate limits), and
`review--bot-re-review.md` (re-review).

## Completeness Invariant

```
unresolved threads == 0  ⟺  all review findings processed
```

GitHub Branch Protection (`required_conversation_resolution`) blocks merge
until every review thread is resolved. This makes the unresolved thread
count a **deterministic completeness guarantee**: if `pr-review` misses a
finding, the corresponding thread remains unresolved and merge is
physically blocked.

## Reply Categories (4, exhaustive)

Every review thread must receive exactly one disposition reply before being
resolved (per `agent-safety.mdc` `HS-REVIEW-RESOLVE`).

| Category | When to use | Template |
|---|---|---|
| **Fixed** | Code change addresses the comment | `Fixed in \`<sha7>\`. <what changed>.` |
| **By design** | Intentional design decision | `By design. <rationale> (ref: <source>).` |
| **False positive** | Bot misidentified an issue | `False positive. <why detection was wrong>.` |
| **Acknowledged** | Valid but out of PR scope | `Acknowledged. <brief assessment>. Tracked in #<issue>.` |

### Examples

**Fixed** — evidence: commit SHA, explanation: what was changed
```
Fixed in `f561c8d`. Aligned timeout values to 20 min across all sections.
```

**By design** — evidence: reference (ADR/rule/command), explanation: design rationale
```
By design. Step 5 auto-loops after initial consent; HS-NO-SKIP ensures
intra-command steps are still followed (ref: next.md § Approval scope).
```

**False positive** — no evidence (the detection itself was wrong), explanation: why
```
False positive. The cross-reference formats differ intentionally —
parenthetical vs dash style matches surrounding sentence structure.
```

**Acknowledged** — evidence: tracking issue, explanation: assessment result
```
Acknowledged. Valid observation; container bootstrap step would improve
usability. Out of scope for SSOT cleanup. Tracked in #201.
```

### Template Design Principles

- **Category keyword first**: grep `^Fixed`, `^By design`, `^False positive`, `^Acknowledged` for machine classification
- **Evidence is minimal and verifiable**: SHA via git, Issue # via GitHub, ref via codebase
- **Explanation is 1-2 sentences**: auditor can understand disposition without opening the thread
- **English**: consistent with code and commit language

## Reply API (REST)

Post a threaded reply to an inline review comment:

```bash
gh api repos/{owner}/{repo}/pulls/<N>/comments/<comment_id>/replies \
  -f body="Fixed in \`abc1234\`. Aligned timeout values to 20 min."
```

`<comment_id>` is the numeric ID of the root comment in the thread (the
bot's original comment, where `in_reply_to_id` is null).

## Resolve API (GraphQL)

Resolve a review thread after posting the disposition reply:

```bash
gh api graphql -f query='
  mutation($id: ID!) {
    resolveReviewThread(input: {threadId: $id}) {
      thread { isResolved }
    }
  }
' -f id="<THREAD_ID>"
```

`<THREAD_ID>` is the GraphQL node ID (e.g., `PRRT_kwDO...`), obtained
from the thread enumeration query in `pr-review.md` Step 6 or `next.md`
Step 1.

## Thread Enumeration (GraphQL)

List all review threads with resolution status:

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

The `databaseId` in the inner comment is the `<comment_id>` needed for
the REST reply API. The outer `id` is the `<THREAD_ID>` needed for the
GraphQL resolve API.

## Procedure (in review-fix)

1. Enumerate unresolved threads (query above)
2. For each thread: classify → post reply → resolve
3. Verify: re-run enumeration, confirm unresolved == 0

See `review-fix.md` Step 3b for the full procedure.

## Edge Cases

- **CodeRabbit `✅ Addressed in commit` marker**: Informational only — does
  NOT exempt the agent from posting a disposition reply and resolving the
  thread.
- **`isOutdated` threads**: The referenced code has changed, but the thread
  is still valid. `required_conversation_resolution` does not distinguish
  outdated from current — all threads must be resolved. This aligns with
  `HS-NO-DISMISS`.
- **Human-replied threads**: If a human (e.g., PR author) already replied
  with a disposition, the agent should still resolve the thread if it
  remains unresolved.
- **Multiple comments in one thread**: Reply once to the root comment; the
  disposition covers the entire thread.

## Related

- `review--bot-trigger.md` — trigger rules and two-tier model
- `review--bot-detection.md` — output detection, state machine, polling
- `review--bot-timing.md` — timing, rate limits, recovery
- `review--bot-re-review.md` — re-review after review-fix
- `agent-safety.mdc` `HS-REVIEW-RESOLVE` — Hard Stop definition
- `workflow-policy.mdc` § Review Comment Response — policy declaration
- `review-fix.md` Step 3b — procedure for reply + resolve
- `pr-review.md` Step 6 — thread enumeration baseline
- `pr-merge.md` — merge precondition (all threads resolved)
