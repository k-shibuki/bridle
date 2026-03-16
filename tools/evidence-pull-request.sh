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

# --- Bot config ---
BOT_CONFIG="$(dirname "$0")/../docs/agent-control/review-bots.json"
if [ ! -f "$BOT_CONFIG" ]; then
  evidence_error "config" "Bot config not found: $BOT_CONFIG" true
  evidence_emit '{}'
  exit 0
fi

bot_config=$(jq -c '.' "$BOT_CONFIG" 2>/dev/null || echo "")
if [ -z "$bot_config" ]; then
  evidence_error "config" "Failed to parse bot config: $BOT_CONFIG" true
  evidence_emit '{}'
  exit 0
fi

if ! echo "$bot_config" | jq -e '
  (.bots | type) == "array" and (.bots | length) > 0 and
  all(.bots[];
    ((.id | type) == "string") and (.id | test("^[a-z0-9_]+$")) and
    ((.display_name | type) == "string") and
    ((.login_pattern | type) == "string") and
    (.match_type == "exact" or .match_type == "regex") and
    (.match_flags == null or ((.match_flags | type) == "string")) and
    (.rate_limit_pattern == null or ((.rate_limit_pattern | type) == "string")) and
    (.max_reviews == null or ((.max_reviews | type) == "number"))
  )
' >/dev/null 2>&1; then
  evidence_error "config" "Invalid bot config schema: $BOT_CONFIG" true
  evidence_emit '{}'
  exit 0
fi

bot_count=$(echo "$bot_config" | jq '.bots | length')

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

# --- Fetch review data (shared across all bots) ---
reviews=$(gh api "repos/$owner/$repo/pulls/$PR/reviews" 2>/dev/null || echo "[]")
pr_comments=$(gh api "repos/$owner/$repo/issues/$PR/comments" 2>/dev/null || echo "[]")
cr_inline=$(gh api "repos/$owner/$repo/pulls/$PR/comments" 2>/dev/null || echo "[]")

# --- Build bot review objects from config ---
# _detect_bot_reviews reads config and review data to produce a JSON object
# for each configured bot.
_detect_bot_reviews() {
  local bot_json="{}"
  local i=0

  while [ "$i" -lt "$bot_count" ]; do
    local bot_id bot_login match_type match_flags rate_limit_pat max_rev
    bot_id=$(echo "$bot_config" | jq -r ".bots[$i].id")
    bot_login=$(echo "$bot_config" | jq -r ".bots[$i].login_pattern")
    match_type=$(echo "$bot_config" | jq -r ".bots[$i].match_type")
    match_flags=$(echo "$bot_config" | jq -r ".bots[$i].match_flags // \"\"")
    rate_limit_pat=$(echo "$bot_config" | jq -r ".bots[$i].rate_limit_pattern // \"\"")
    max_rev=$(echo "$bot_config" | jq ".bots[$i].max_reviews // null")

    local status="NOT_TRIGGERED"
    local submitted=""
    local findings=0
    local review_count=0

    # Build jq filter for login matching
    local jq_login_filter
    if [ "$match_type" = "exact" ]; then
      jq_login_filter="select(.user.login == \"$bot_login\")"
    else
      if [ -n "$match_flags" ]; then
        jq_login_filter="select(.user.login | test(\"$bot_login\"; \"$match_flags\"))"
      else
        jq_login_filter="select(.user.login | test(\"$bot_login\"))"
      fi
    fi

    # Reviews from this bot
    local bot_reviews_all
    bot_reviews_all=$(echo "$reviews" | jq -c "[.[] | $jq_login_filter]")
    review_count=$(echo "$bot_reviews_all" | jq 'length')

    local latest_review
    latest_review=$(echo "$bot_reviews_all" | jq -c 'sort_by(.submitted_at) | last // empty' 2>/dev/null || echo "")
    if [ -n "$latest_review" ]; then
      status="COMPLETED"
      submitted=$(echo "$latest_review" | jq -r '.submitted_at // ""')
    fi

    # Rate limit detection via PR comments
    if [ -n "$rate_limit_pat" ] && [ "$rate_limit_pat" != "null" ]; then
      local rl_count
      if [ "$match_type" = "exact" ]; then
        rl_count=$(echo "$pr_comments" | jq "[.[] | select(.user.login == \"$bot_login\" and (.body | test(\"$rate_limit_pat\")))] | length")
      else
        if [ -n "$match_flags" ]; then
          rl_count=$(echo "$pr_comments" | jq "[.[] | select((.user.login | test(\"$bot_login\"; \"$match_flags\")) and (.body | test(\"$rate_limit_pat\")))] | length")
        else
          rl_count=$(echo "$pr_comments" | jq "[.[] | select((.user.login | test(\"$bot_login\")) and (.body | test(\"$rate_limit_pat\")))] | length")
        fi
      fi
      if [ "$rl_count" -gt 0 ] && [ "$status" = "NOT_TRIGGERED" ]; then
        status="RATE_LIMITED"
      fi
    fi

    # Inline findings count (top-level only, excluding reply comments)
    if [ "$match_type" = "exact" ]; then
      findings=$(echo "$cr_inline" | jq "[.[] | select(.user.login == \"$bot_login\" and (.in_reply_to_id // null) == null)] | length")
    else
      if [ -n "$match_flags" ]; then
        findings=$(echo "$cr_inline" | jq "[.[] | select((.user.login | test(\"$bot_login\"; \"$match_flags\")) and (.in_reply_to_id // null) == null)] | length")
      else
        findings=$(echo "$cr_inline" | jq "[.[] | select((.user.login | test(\"$bot_login\")) and (.in_reply_to_id // null) == null)] | length")
      fi
    fi

    # Body-embedded findings aggregated across all reviews
    local body_count
    body_count=$(echo "$bot_reviews_all" | jq '
      [.[].body // ""
       | try (capture("Outside diff range comments \\((?<count>\\d+)\\)").count | tonumber) catch empty
      ] | add // 0
    ')
    findings=$((findings + body_count))

    # Compose bot entry
    local bot_entry
    bot_entry=$(jq -nc \
      --arg status "$status" \
      --arg sub "$submitted" \
      --argjson findings "$findings" \
      --argjson review_count "$review_count" \
      --argjson max_rev "$max_rev" \
      '{
        "status": $status,
        "review_submitted_at": (if $sub == "" then null else $sub end),
        "findings_count": $findings,
        "review_count": $review_count,
        "max_reviews": $max_rev
      }')

    bot_json=$(echo "$bot_json" | jq -c --arg key "bot_$bot_id" --argjson val "$bot_entry" \
      '. + {($key): $val}')

    i=$((i + 1))
  done

  echo "$bot_json"
}

bot_reviews=$(_detect_bot_reviews)

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
# Build a jq filter that excludes all configured bot logins from human review
_build_bot_exclusion_filter() {
  local filter=""
  local i=0
  while [ "$i" -lt "$bot_count" ]; do
    local bot_login match_type match_flags
    bot_login=$(echo "$bot_config" | jq -r ".bots[$i].login_pattern")
    match_type=$(echo "$bot_config" | jq -r ".bots[$i].match_type")
    match_flags=$(echo "$bot_config" | jq -r ".bots[$i].match_flags // \"\"")

    if [ -n "$filter" ]; then
      filter="$filter and "
    fi

    if [ "$match_type" = "exact" ]; then
      filter="${filter}.user.login != \"$bot_login\""
    else
      if [ -n "$match_flags" ]; then
        filter="${filter}(.user.login | test(\"$bot_login\"; \"$match_flags\") | not)"
      else
        filter="${filter}(.user.login | test(\"$bot_login\") | not)"
      fi
    fi

    i=$((i + 1))
  done
  # Also exclude github-actions[bot]
  filter="${filter} and .user.login != \"github-actions[bot]\""
  echo "$filter"
}

bot_exclusion=$(_build_bot_exclusion_filter)

disposition="pending"
latest_review=$(echo "$reviews" | jq -r "[.[] | select($bot_exclusion)] | sort_by(.submitted_at) | last // empty | .state // \"\"" 2>/dev/null || echo "")
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
  --argjson bot_reviews "$bot_reviews" \
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
    "reviews": (
      $bot_reviews + {
        "threads_total": $threads_total,
        "threads_unresolved": $threads_unresolved,
        "disposition": $disposition,
        "last_review_at": (if $last_review == "" then null else $last_review end),
        "last_push_at": $last_push
      }
    ),
    "traceability": {
      "closes_issues": $closes,
      "has_exception_label": $has_exc,
      "exception_type": $exc_type
    }
  }')

evidence_emit "$body"
