#!/usr/bin/env bash
# tools/evidence-review-threads.sh -- Per-thread review details for review-fix/pr-review
# Requires PR= argument: make evidence-review-threads PR=232
# Network access: GitHub GraphQL + REST API
set -euo pipefail
# shellcheck disable=SC1091 source=evidence-lib.sh
. "$(dirname "$0")/evidence-lib.sh"

evidence_init "evidence-review-threads"

PR="${PR:-}"
if [ -z "$PR" ]; then
  evidence_error "argument" "PR= argument is required" true
  evidence_emit '{}'
  exit 0
fi

owner=$(gh repo view --json owner --jq '.owner.login' 2>/dev/null || echo "")
repo=$(gh repo view --json name --jq '.name' 2>/dev/null || echo "")

if [ -z "$owner" ] || [ -z "$repo" ]; then
  evidence_error "gh" "Could not determine repo owner/name" true
  evidence_emit '{}'
  exit 0
fi

# --- Review threads with full detail ---
# shellcheck disable=SC2016
threads_json=$(gh api graphql -f query='
  query($owner: String!, $repo: String!, $pr: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $pr) {
        reviewThreads(first: 100) {
          totalCount
          nodes {
            id
            isResolved
            isOutdated
            path
            line
            comments(first: 20) {
              nodes {
                databaseId
                author { login }
                body
                createdAt
              }
            }
          }
        }
      }
    }
  }
' -f owner="$owner" -f repo="$repo" -F pr="$PR" 2>/dev/null || echo "")

if [ -z "$threads_json" ]; then
  evidence_error "graphql" "Failed to fetch review threads" true
  evidence_emit '{}'
  exit 0
fi

threads=$(echo "$threads_json" | jq -c '{
  total: .data.repository.pullRequest.reviewThreads.totalCount,
  unresolved: [.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved | not)] | length,
  threads: [.data.repository.pullRequest.reviewThreads.nodes[] | {
    graphql_id: .id,
    is_resolved: .isResolved,
    is_outdated: .isOutdated,
    path: .path,
    line: .line,
    author: .comments.nodes[0].author.login,
    body: .comments.nodes[0].body,
    database_id: .comments.nodes[0].databaseId,
    replies: [.comments.nodes[1:][] | {
      database_id: .databaseId,
      author: .author.login,
      body: .body,
      created_at: .createdAt
    }]
  }]
}')

# --- Changed files ---
files_changed=$(gh pr diff "$PR" --name-only 2>/dev/null | jq -Rsc 'split("\n") | map(select(. != ""))') || files_changed="[]"

# --- Compose output ---
body=$(echo "$threads" | jq -c --argjson files "$files_changed" \
  '. + {"files_changed": $files}')

evidence_emit "$body"
