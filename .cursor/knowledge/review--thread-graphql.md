---
trigger: GraphQL thread enumeration, review thread query, unresolved thread count, thread baseline, PR review threads, isResolved
---
# Review Thread GraphQL Enumeration

Query to enumerate PR review threads for completeness verification.
Used by `pr-review` (Step 6) and `review-fix` (Step 3b) to establish
a thread baseline and verify all findings have consensus.

## Thread enumeration query

```bash
gh api graphql -f query='
  query($owner: String!, $repo: String!, $pr: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $pr) {
        reviewThreads(first: 100) {
          totalCount
          nodes { id isResolved isOutdated
            comments(first: 1) { nodes { author { login } body } }
          }
        }
      }
    }
  }
' -f owner={owner} -f repo={repo} -F pr=<N> --jq '{
  total: .data.repository.pullRequest.reviewThreads.totalCount,
  unresolved: [.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved | not)] | length,
  resolved: [.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved)] | length
}'
```

## Completeness check

- **Thread baseline**: X total, Y unresolved, Z resolved
- **Classified findings**: N (must equal Y for completeness)
- **Delta** (Y - N): if > 0, findings were missed — re-examine unresolved threads
