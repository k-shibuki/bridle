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

_resolve_repo
owner="$REPO_OWNER"
repo="$REPO_NAME"

if [ -z "$owner" ] || [ -z "$repo" ]; then
  evidence_error "gh" "Could not determine repo owner/name from git remote" true
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
          pageInfo { hasNextPage }
          nodes {
            id
            isResolved
            isOutdated
            path
            line
            comments(first: 20) {
              pageInfo { hasNextPage }
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

if ! echo "$threads_json" | jq -e '.data.repository.pullRequest.reviewThreads != null' >/dev/null; then
  evidence_error "graphql" "PR #$PR not found or inaccessible" true
  evidence_emit '{}'
  exit 0
fi

# --- Truncation detection ---
threads_truncated=$(echo "$threads_json" | jq '.data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage // false')
comments_truncated=$(echo "$threads_json" | jq '[.data.repository.pullRequest.reviewThreads.nodes[].comments.pageInfo.hasNextPage] | any')
truncated=false
if [ "$threads_truncated" = "true" ]; then
  truncated=true
  evidence_error "pagination" "reviewThreads has more pages (>100 threads)" false
fi
if [ "$comments_truncated" = "true" ]; then
  truncated=true
  evidence_error "pagination" "One or more threads have >20 comments" false
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

# --- Body-embedded findings (outside diff range comments in review body) ---
reviews_rest=$(gh api "repos/$owner/$repo/pulls/$PR/reviews" 2>/dev/null || echo "[]")

body_findings="[]"
body_findings_count=0

while IFS= read -r review_line; do
  [ -z "$review_line" ] && continue
  review_id=$(echo "$review_line" | jq -r '.id')
  review_author=$(echo "$review_line" | jq -r '.user.login')
  submitted_at=$(echo "$review_line" | jq -r '.submitted_at')
  review_body=$(echo "$review_line" | jq -r '.body // ""')

  current_path=""
  pending_line_range=""

  while IFS= read -r line; do
    # File section: <summary>filepath (N)</summary>
    if [[ "$line" =~ \<summary\>([^'<']+)\ \([0-9]+\)\</summary\> ]]; then
      candidate="${BASH_REMATCH[1]}"
      if [[ ! "$candidate" =~ Outside\ diff\ range ]]; then
        current_path="$candidate"
      fi
      continue
    fi

    # Line range: `NNN-NNN`: or `NNN`:
    if [ -n "$current_path" ] && [[ "$line" =~ \`([0-9]+(-[0-9]+)?)\`\: ]]; then
      pending_line_range="${BASH_REMATCH[1]}"
      continue
    fi

    # Finding title: **text**
    if [ -n "$pending_line_range" ] && [[ "$line" =~ \*\*(.+)\*\* ]]; then
      title="${BASH_REMATCH[1]}"
      finding=$(jq -nc \
        --arg review_id "$review_id" \
        --arg author "$review_author" \
        --arg path "$current_path" \
        --arg line_range "$pending_line_range" \
        --arg body "$title" \
        --arg submitted_at "$submitted_at" \
        '{review_id: ($review_id | tonumber), author: $author, path: $path, line_range: $line_range, body: $body, submitted_at: $submitted_at}')
      body_findings=$(echo "$body_findings" | jq -c --argjson f "$finding" '. + [$f]')
      body_findings_count=$((body_findings_count + 1))
      pending_line_range=""
      continue
    fi
  done <<< "$review_body"
done < <(echo "$reviews_rest" | jq -c '.[] | select(.body | test("Outside diff range comments"))')

# --- Changed files ---
if files_changed=$(gh pr diff "$PR" --name-only 2>/dev/null | jq -Rsc 'split("\n") | map(select(. != ""))'); then
  :
else
  evidence_error "gh" "Failed to fetch changed files" false
  files_changed="[]"
fi

# --- Compose output ---
body=$(echo "$threads" | jq -c \
  --argjson files "$files_changed" \
  --argjson trunc "$truncated" \
  --argjson bf "$body_findings" \
  --argjson bfc "$body_findings_count" \
  '. + {"body_findings": $bf, "body_findings_count": $bfc, "files_changed": $files, "truncated": $trunc}')

evidence_emit "$body"
