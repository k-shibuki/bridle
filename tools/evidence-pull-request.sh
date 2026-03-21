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
    (.invalidate_review_pattern == null or ((.invalidate_review_pattern | type) == "string")) and
    (.max_reviews == null or ((.max_reviews | type) == "number")) and
    ((.required | type) == "boolean") and
    (.commit_status_name == null or ((.commit_status_name | type) == "string")) and
    ((.trigger | type) == "string") and (.trigger == "agent" or .trigger == "user_only") and
    (.fallback_priority == null or ((.fallback_priority | type) == "number"))
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

# --- CI status (exclude bot commit-status checks listed in review-bots.json) ---
ci_checks=$(echo "$pr_data" | jq -c --argjson cfg "$bot_config" '
  (.statusCheckRollup // []) as $roll
  | ([$cfg.bots[] | (.commit_status_name // "") | select(length > 0) | ascii_downcase]) as $npats
  | (if ($npats | length) == 0 then $roll else
      [ $roll[] | select(
          .name as $cn
          | [ $npats[] as $p | ($cn | ascii_downcase | contains($p)) ] | any | not
        )]
    end) as $filtered
  | [ $filtered[] | {
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
  }]
')

ci_status=$(echo "$pr_data" | jq -r --argjson cfg "$bot_config" '
  (.statusCheckRollup // []) as $roll
  | ([$cfg.bots[] | (.commit_status_name // "") | select(length > 0) | ascii_downcase]) as $npats
  | (if ($npats | length) == 0 then $roll else
      [ $roll[] | select(
          .name as $cn
          | [ $npats[] as $p | ($cn | ascii_downcase | contains($p)) ] | any | not
        )]
    end) as $filtered
  | if ($filtered | length) == 0 then "no_checks"
  elif [$filtered[] | select(.conclusion == "FAILURE")] | length > 0 then "failure"
  elif [$filtered[] | select(.status != "COMPLETED")] | length > 0 then "pending"
  else "success"
  end
')

# --- Merge status ---
mergeable=$(echo "$pr_data" | jq -r '.mergeable // "UNKNOWN"')
merge_state=$(echo "$pr_data" | jq -r '.mergeStateStatus // "UNKNOWN"')

# Head push time — bot status must ignore stale reviews / rate-limit comments from prior pushes
last_push_at=$(echo "$pr_data" | jq -r '.commits[-1].committedDate // ""')

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
    local invalidate_pat
    invalidate_pat=$(echo "$bot_config" | jq -r ".bots[$i].invalidate_review_pattern // \"\"")
    max_rev=$(echo "$bot_config" | jq ".bots[$i].max_reviews // null")
    local commit_cs_name
    commit_cs_name=$(echo "$bot_config" | jq -r ".bots[$i].commit_status_name // \"\"")

    local status="NOT_TRIGGERED"
    local submitted=""
    local findings=0
    local review_count=0

    # Reviews from this bot (uses --arg to safely pass regex patterns)
    local bot_reviews_all
    if [ "$match_type" = "exact" ]; then
      bot_reviews_all=$(echo "$reviews" | jq -c --arg login "$bot_login" '[.[] | select(.user.login == $login)]')
    else
      if [ -n "$match_flags" ]; then
        bot_reviews_all=$(echo "$reviews" | jq -c --arg pat "$bot_login" --arg flags "$match_flags" '[.[] | select(.user.login | test($pat; $flags))]')
      else
        bot_reviews_all=$(echo "$reviews" | jq -c --arg pat "$bot_login" '[.[] | select(.user.login | test($pat))]')
      fi
    fi
    review_count=$(echo "$bot_reviews_all" | jq 'length')

    # GitHub commit status (CodeRabbit) — primary when commit_status_name matches rollup (Refs: #273)
    local used_commit_status=false
    if [ -n "$commit_cs_name" ] && [ "$commit_cs_name" != "null" ]; then
      local cs_row_json
      cs_row_json=$(echo "$pr_data" | jq -c --arg pat "$commit_cs_name" '
        (.statusCheckRollup // []) as $r
        | [ $r[] | select(.name | ascii_downcase | contains($pat | ascii_downcase)) ] as $m
        | if ($m | length) == 0 then null
          else (
            $m
            | sort_by(
                if .status != "COMPLETED" then 0
                elif .conclusion == "FAILURE" then 1
                elif .conclusion == "SUCCESS" then 2
                else 3 end
              )
            | .[0]
          )
        end
      ')
      if [ -n "$cs_row_json" ] && [ "$cs_row_json" != "null" ]; then
        used_commit_status=true
        local cs_line
        cs_line=$(echo "$cs_row_json" | jq -r '
          if .status != "COMPLETED" then "pending"
          elif .conclusion == "SUCCESS" then "success"
          elif .conclusion == "FAILURE" then "failure"
          else "pending"
          end
        ')
        case "$cs_line" in
          success)
            status="COMPLETED"
            submitted=$(echo "$cs_row_json" | jq -r '.completedAt // empty')
            if [ -z "$submitted" ] || [ "$submitted" = "null" ]; then
              submitted="$last_push_at"
            fi
            ;;
          pending)
            status="PENDING"
            ;;
          failure)
            status="RATE_LIMITED"
            submitted=""
            ;;
          *)
            status="PENDING"
            ;;
        esac
      fi
    fi

    # Fallback: fresh review (submitted_at >= last push) vs rate-limit comments since last push (timestamp order)
    local bot_status_json
    if [ "$used_commit_status" = false ]; then
      bot_status_json=$(jq -nc \
      --argjson revs "$bot_reviews_all" \
      --argjson comments "$pr_comments" \
      --arg login_pat "$bot_login" \
      --arg match_type "$match_type" \
      --arg match_flags "$match_flags" \
      --arg rlpat "$rate_limit_pat" \
      --arg last_push "$last_push_at" \
      '
      def ts($s):
        if $s == null or $s == "" then null else (try ($s | fromdateiso8601) catch null) end;
      ($last_push | ts(.)) as $tpush
      | (if $tpush == null then 0 else $tpush end) as $tp
      | (if $match_type == "exact" then
          [ $revs[] | select(.user.login == $login_pat) ]
        elif ($match_flags != null and $match_flags != "") then
          [ $revs[] | select(.user.login | test($login_pat; $match_flags)) ]
        else
          [ $revs[] | select(.user.login | test($login_pat)) ]
        end) as $allrev
      | ([ $allrev[] | select((.submitted_at | ts(.)) != null and (.submitted_at | ts(.)) >= $tp) ]
        | sort_by(.submitted_at)) as $fresh
      | (if ($fresh | length) > 0 then ($fresh | last) else null end) as $latest_fresh
      | (if ($rlpat == null or $rlpat == "" or $rlpat == "null") then []
        elif $match_type == "exact" then
          [ $comments[] | select(.user.login == $login_pat and (.body | test($rlpat))) ]
        elif ($match_flags != null and $match_flags != "") then
          [ $comments[] | select((.user.login | test($login_pat; $match_flags)) and (.body | test($rlpat))) ]
        else
          [ $comments[] | select((.user.login | test($login_pat)) and (.body | test($rlpat))) ]
        end
        | map(select((.created_at | ts(.)) != null and (.created_at | ts(.)) >= $tp))
        ) as $rlc
      | (if ($rlc | length) == 0 then null else ([$rlc[] | .created_at | ts(.)] | max) end) as $max_rl_ts
      | (if $latest_fresh == null then null else ($latest_fresh.submitted_at | ts(.)) end) as $max_rev_ts
      | if $latest_fresh != null and ($max_rl_ts == null or $max_rev_ts >= $max_rl_ts) then
          {status: "COMPLETED", submitted: $latest_fresh.submitted_at}
        elif $max_rl_ts != null then
          {status: "RATE_LIMITED", submitted: (if $latest_fresh != null then $latest_fresh.submitted_at else null end)}
        else
          {status: "NOT_TRIGGERED", submitted: null}
        end
      ')
      status=$(echo "$bot_status_json" | jq -r '.status')
      submitted=$(echo "$bot_status_json" | jq -r '.submitted // ""')
      if [ "$submitted" = "null" ]; then
        submitted=""
      fi
    fi

    # CodeRabbit (etc.): PR issue comment when review was voided mid-run (e.g. head moved while CR was reviewing)
    if [ -n "$invalidate_pat" ] && [ "$invalidate_pat" != "null" ]; then
      local inv_count
      if [ "$match_type" = "exact" ]; then
        inv_count=$(echo "$pr_comments" | jq -r --arg login "$bot_login" --arg ipat "$invalidate_pat" --arg lp "$last_push_at" '
          def ts($s): if $s == null or $s == "" then null else (try ($s | fromdateiso8601) catch null) end;
          ($lp | ts(.)) as $tpush | (if $tpush == null then 0 else $tpush end) as $tp
          | [.[] | select(.user.login == $login and (.body | test($ipat)) and ((.created_at | ts(.)) != null) and ((.created_at | ts(.)) >= $tp))]
          | length
        ')
      else
        if [ -n "$match_flags" ]; then
          inv_count=$(echo "$pr_comments" | jq -r --arg pat "$bot_login" --arg flags "$match_flags" --arg ipat "$invalidate_pat" --arg lp "$last_push_at" '
            def ts($s): if $s == null or $s == "" then null else (try ($s | fromdateiso8601) catch null) end;
            ($lp | ts(.)) as $tpush | (if $tpush == null then 0 else $tpush end) as $tp
            | [.[] | select((.user.login | test($pat; $flags)) and (.body | test($ipat)) and ((.created_at | ts(.)) != null) and ((.created_at | ts(.)) >= $tp))]
            | length
          ')
        else
          inv_count=$(echo "$pr_comments" | jq -r --arg pat "$bot_login" --arg ipat "$invalidate_pat" --arg lp "$last_push_at" '
            def ts($s): if $s == null or $s == "" then null else (try ($s | fromdateiso8601) catch null) end;
            ($lp | ts(.)) as $tpush | (if $tpush == null then 0 else $tpush end) as $tp
            | [.[] | select((.user.login | test($pat)) and (.body | test($ipat)) and ((.created_at | ts(.)) != null) and ((.created_at | ts(.)) >= $tp))]
            | length
          ')
        fi
      fi
      if [ "${inv_count:-0}" -gt 0 ] 2>/dev/null; then
        status="REVIEW_INVALIDATED"
        submitted=""
      fi
    fi

    # Inline findings count (top-level only, excluding reply comments)
    if [ "$match_type" = "exact" ]; then
      findings=$(echo "$cr_inline" | jq --arg login "$bot_login" \
        '[.[] | select(.user.login == $login and (.in_reply_to_id // null) == null)] | length')
    else
      if [ -n "$match_flags" ]; then
        findings=$(echo "$cr_inline" | jq --arg pat "$bot_login" --arg flags "$match_flags" \
          '[.[] | select((.user.login | test($pat; $flags)) and (.in_reply_to_id // null) == null)] | length')
      else
        findings=$(echo "$cr_inline" | jq --arg pat "$bot_login" \
          '[.[] | select((.user.login | test($pat)) and (.in_reply_to_id // null) == null)] | length')
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
# Filter out bot reviews to find human review disposition
_get_human_disposition() {
  local bot_specs
  bot_specs=$(echo "$bot_config" | jq -c '[.bots[] | {login_pattern, match_type, match_flags}]')

  echo "$reviews" | jq -r --argjson bots "$bot_specs" '
    def is_bot($login):
      ($bots | any(
        . as $bot
        | if $bot.match_type == "exact" then $login == $bot.login_pattern
        elif ($bot.match_flags // "") != "" then $login | test($bot.login_pattern; $bot.match_flags)
        else $login | test($bot.login_pattern)
        end
      )) or ($login == "github-actions[bot]");
    [.[] | select(.user.login | is_bot(.) | not)]
    | sort_by(.submitted_at) | last // empty | .state // ""
  ' 2>/dev/null || echo ""
}

disposition="pending"
latest_review=$(_get_human_disposition)
case "$latest_review" in
  APPROVED) disposition="approved" ;;
  CHANGES_REQUESTED) disposition="changes_requested" ;;
  *) disposition="pending" ;;
esac

# --- FSM-derived review signals (Refs: #272). REVIEW_INVALIDATED = voided bot run for current head (not Reviewed / not Failed).
review_signals=$(jq -nc \
  --argjson bots_map "$bot_reviews" \
  --argjson cfg "$bot_config" \
  --arg disposition "$disposition" \
  --argjson threads_u "$threads_unresolved" \
  '
  def reviewed($s):
    $s == "COMPLETED" or $s == "COMPLETED_CLEAN" or $s == "COMPLETED_SILENT";
  def failed($s):
    $s == "RATE_LIMITED" or $s == "TIMED_OUT";
  [ $cfg.bots[] | . as $b
    | ($bots_map["bot_\($b.id)"].status // "NOT_TRIGGERED") as $st
    | {required: $b.required, status: $st}
  ] as $rows
  | ($rows | any(.required and failed(.status))) as $failed
  | ($rows | all(if .required then reviewed(.status) else (reviewed(.status) or (.status == "NOT_TRIGGERED") or (.status == "REVIEW_INVALIDATED")) end)) as $completed
  | ($failed or $completed) as $terminal
  | ($terminal | not) as $pending
  | (($disposition == "approved") or ($disposition == "pending" and $completed and $threads_u == 0)) as $concluded
  | {
      bot_review_completed: $completed,
      bot_review_failed: $failed,
      bot_review_terminal: $terminal,
      bot_review_pending: $pending,
      review_concluded: $concluded
    }
  ')

# --- Timestamps ---
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
  --argjson signals "$review_signals" \
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
      } + $signals
    ),
    "traceability": {
      "closes_issues": $closes,
      "has_exception_label": $has_exc,
      "exception_type": $exc_type
    }
  }')

evidence_emit "$body"
