#!/usr/bin/env bash
# tools/evidence-pull-request.sh -- Detailed PR state
# Requires PR= argument: make evidence-pull-request PR=229
# Network access: GitHub REST + GraphQL API
set -euo pipefail
# shellcheck disable=SC1091 source=evidence-lib.sh
. "$(dirname "$0")/evidence-lib.sh"

evidence_init "evidence-pull-request"

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

# --- PR basic info ---
pr_data=$(gh pr view "$PR" \
  --json number,title,state,headRefName,baseRefName,mergeable,mergeStateStatus,statusCheckRollup,reviews,labels,body,commits \
  2>/dev/null || echo "")

if [ -z "$pr_data" ]; then
  evidence_error "gh pr view" "PR #$PR not found" true
  evidence_emit '{}'
  exit 0
fi

number=$(echo "$pr_data" | jq '.number')
title=$(echo "$pr_data" | jq -r '.title')
pr_state=$(echo "$pr_data" | jq -r '.state // "UNKNOWN"')
head_branch=$(echo "$pr_data" | jq -r '.headRefName')
base_branch=$(echo "$pr_data" | jq -r '.baseRefName')

# --- CI status ---
ci_checks=$(echo "$pr_data" | jq -c '[(.statusCheckRollup // [])[] | {
  name: .name,
  status: (
    if .status != "COMPLETED" then "pending"
    elif .conclusion == "SUCCESS" then "pass"
    elif .conclusion == "FAILURE" then "fail"
    elif .conclusion == "SKIPPED" then "skipped"
    else "pending"
    end
  ),
  elapsed_seconds: (
    if .completedAt != null and .startedAt != null then
      ((.completedAt | fromdateiso8601) - (.startedAt | fromdateiso8601))
    else null
    end
  )
}]')

ci_status=$(echo "$pr_data" | jq -r '
  if (.statusCheckRollup | length) == 0 then "no_checks"
  elif [.statusCheckRollup[] | select(.conclusion == "FAILURE")] | length > 0 then "failure"
  elif [.statusCheckRollup[] | select(.status != "COMPLETED")] | length > 0 then "pending"
  else "success"
  end
')

# --- Merge status ---
mergeable=$(echo "$pr_data" | jq -r '.mergeable // "UNKNOWN"')
merge_state=$(echo "$pr_data" | jq -r '.mergeStateStatus // "UNKNOWN"')

# --- Reviews and bot status ---
coderabbit_status="NOT_TRIGGERED"
coderabbit_submitted=""
coderabbit_findings=0
codex_status="NOT_TRIGGERED"
codex_submitted=""
codex_findings=0

reviews=$(gh api "repos/$owner/$repo/pulls/$PR/reviews" 2>/dev/null || echo "[]")

cr_reviews_all=$(echo "$reviews" | jq -c '[.[] | select(.user.login == "coderabbitai[bot]")]')
cr_review_count=$(echo "$cr_reviews_all" | jq 'length')
cr_review=$(echo "$cr_reviews_all" | jq -c 'sort_by(.submitted_at) | last // empty' 2>/dev/null || echo "")
if [ -n "$cr_review" ]; then
  coderabbit_status="COMPLETED"
  coderabbit_submitted=$(echo "$cr_review" | jq -r '.submitted_at // ""')
fi

codex_review=$(echo "$reviews" | jq -c '[.[] | select(.user.login | test("codex|chatgpt"; "i"))] | sort_by(.submitted_at) | last // empty' 2>/dev/null || echo "")
if [ -n "$codex_review" ]; then
  codex_status="COMPLETED"
  codex_submitted=$(echo "$codex_review" | jq -r '.submitted_at // ""')
fi

# Check for rate limit in PR comments
pr_comments=$(gh api "repos/$owner/$repo/issues/$PR/comments" 2>/dev/null || echo "[]")
cr_rate_limit=$(echo "$pr_comments" | jq '[.[] | select(.user.login == "coderabbitai[bot]" and (.body | test("Rate limit exceeded")))] | length')
if [ "$cr_rate_limit" -gt 0 ] && [ "$coderabbit_status" = "NOT_TRIGGERED" ]; then
  coderabbit_status="RATE_LIMITED"
fi

# Inline findings count (review comments on specific lines)
cr_inline=$(gh api "repos/$owner/$repo/pulls/$PR/comments" 2>/dev/null || echo "[]")
coderabbit_findings=$(echo "$cr_inline" | jq '[.[] | select(.user.login == "coderabbitai[bot]")] | length')
codex_findings=$(echo "$cr_inline" | jq '[.[] | select(.user.login | test("codex|chatgpt"; "i"))] | length')

# Body-embedded findings ("Outside diff range comments" in review body)
if [ -n "$cr_review" ]; then
  cr_body_count=$(echo "$cr_review" | jq -r '.body // ""' \
    | grep -oP 'Outside diff range comments \(\K\d+' || echo 0)
  cr_body_count=${cr_body_count:-0}
  coderabbit_findings=$((coderabbit_findings + cr_body_count))
fi

# --- Thread state ---
# shellcheck disable=SC2016
threads=$(gh api graphql -f query='
  query($owner: String!, $repo: String!, $pr: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $pr) {
        reviewThreads(first: 100) {
          totalCount
          nodes { isResolved }
        }
      }
    }
  }
' -f owner="$owner" -f repo="$repo" -F pr="$PR" \
  --jq '{
    total: .data.repository.pullRequest.reviewThreads.totalCount,
    unresolved: [.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved | not)] | length
  }' 2>/dev/null || echo '{"total":0,"unresolved":0}')

threads_total=$(echo "$threads" | jq '.total')
threads_unresolved=$(echo "$threads" | jq '.unresolved')

# --- Disposition ---
disposition="pending"
latest_review=$(echo "$reviews" | jq -r '[.[] | select(.user.login != "coderabbitai[bot]" and .user.login != "github-actions[bot]" and (.user.login | test("codex|chatgpt"; "i") | not))] | sort_by(.submitted_at) | last // empty | .state // ""' 2>/dev/null || echo "")
case "$latest_review" in
  APPROVED) disposition="approved" ;;
  CHANGES_REQUESTED) disposition="changes_requested" ;;
  *) disposition="pending" ;;
esac

# --- Timestamps ---
last_push_at=$(echo "$pr_data" | jq -r '.commits[-1].committedDate // ""')
last_review_at=$(echo "$reviews" | jq -r '[.[].submitted_at] | sort | last // ""')
[ "$last_review_at" = "null" ] && last_review_at=""

# --- Traceability ---
pr_body=$(echo "$pr_data" | jq -r '.body // ""')
closes_issues=$(echo "$pr_body" | jq -Rsc '
  [scan("(?i)(?:closes|fixes|resolves)\\s+#(\\d+)") | .[0] | tonumber] | unique')
has_exception=$(echo "$pr_data" | jq '[.labels[].name] | any(. == "no-issue" or . == "hotfix")')
exception_type="null"
if [ "$has_exception" = "true" ]; then
  exception_type=$(echo "$pr_data" | jq '[.labels[].name] | map(select(. == "no-issue" or . == "hotfix")) | first // null')
fi

# --- Compose output ---
body=$(jq -nc \
  --argjson number "$number" \
  --arg title "$title" \
  --arg state "$pr_state" \
  --arg head "$head_branch" \
  --arg base "$base_branch" \
  --arg ci_status "$ci_status" \
  --argjson ci_checks "$ci_checks" \
  --arg mergeable "$mergeable" \
  --arg merge_state "$merge_state" \
  --arg cr_status "$coderabbit_status" \
  --arg cr_sub "$coderabbit_submitted" \
  --argjson cr_findings "$coderabbit_findings" \
  --argjson cr_count "$cr_review_count" \
  --arg cx_status "$codex_status" \
  --arg cx_sub "$codex_submitted" \
  --argjson cx_findings "$codex_findings" \
  --argjson threads_total "$threads_total" \
  --argjson threads_unresolved "$threads_unresolved" \
  --arg disposition "$disposition" \
  --arg last_review "$last_review_at" \
  --arg last_push "$last_push_at" \
  --argjson closes "$closes_issues" \
  --argjson has_exc "$has_exception" \
  --argjson exc_type "$exception_type" \
  '{
    "number": $number,
    "title": $title,
    "state": $state,
    "head_branch": $head,
    "base_branch": $base,
    "ci": {
      "status": $ci_status,
      "checks": $ci_checks
    },
    "merge": {
      "mergeable": $mergeable,
      "merge_state_status": $merge_state
    },
    "reviews": {
      "bot_coderabbit": {
        "status": $cr_status,
        "review_submitted_at": (if $cr_sub == "" then null else $cr_sub end),
        "findings_count": $cr_findings,
        "review_count": $cr_count
      },
      "bot_codex": {
        "status": $cx_status,
        "review_submitted_at": (if $cx_sub == "" then null else $cx_sub end),
        "findings_count": $cx_findings
      },
      "threads_total": $threads_total,
      "threads_unresolved": $threads_unresolved,
      "disposition": $disposition,
      "last_review_at": (if $last_review == "" then null else $last_review end),
      "last_push_at": $last_push
    },
    "traceability": {
      "closes_issues": $closes,
      "has_exception_label": $has_exc,
      "exception_type": $exc_type
    }
  }')

evidence_emit "$body"
