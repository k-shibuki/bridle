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
    (.fallback_priority == null or ((.fallback_priority | type) == "number")) and
    (.skip_patterns == null or ((.skip_patterns | type) == "array" and all(.skip_patterns[]; (type == "string")))) and
    (.skip_policy == null or .skip_policy == "terminal_clean" or .skip_policy == "terminal_blocked")
  )
' >/dev/null 2>&1; then
  evidence_error "config" "Invalid bot config schema: $BOT_CONFIG" true
  evidence_emit '{}'
  exit 0
fi

bot_count=$(echo "$bot_config" | jq '.bots | length')
_JQ_DIR="$(cd "$(dirname "$0")" && pwd)/jq"
_evidence_ci_gate() {
  jq -n \
    --argjson rollup "$(echo "$pr_data" | jq -c '.statusCheckRollup // []')" \
    --argjson cfg "$bot_config" \
    -f <(cat "$_JQ_DIR/evidence-ci-gate-defs.jq" "$_JQ_DIR/evidence-ci-gate-single.jq")
}

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

# --- CI rollup excluding bot-named checks (same filter as tools/jq/evidence-ci-gate-defs.jq + review-bots.json commit_status_name) ---
_ci_gate_json=$(_evidence_ci_gate)
ci_checks=$(echo "$_ci_gate_json" | jq -c '.ci_checks')
ci_status=$(echo "$_ci_gate_json" | jq -r '.ci_status')
unset _ci_gate_json

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
# Status resolution order: (1) commit-status row whose name equals commit_status_name (case-insensitive);
# (2) issue comments matching rate_limit_pattern since head commit may override (1) for stale success or pending;
# (3) if (1) unused, compare fresh PR reviews vs rate-limit comments since head;
# (4) invalidate_review_pattern on issue comments since head forces REVIEW_INVALIDATED.
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
    local rate_limit_meta="null"
    local skip_detected=false
    local skip_reason=""
    local skip_detected_at=""

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
        | ($pat | ascii_downcase) as $p
        | [ $r[] | select((.name // "") | ascii_downcase == $p) ] as $m
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
            rate_limit_meta=$(jq -nc --argjson cs "$cs_row_json" \
              '{detected: true, source: "commit_status_row", check_name: ($cs.name // null), conclusion: ($cs.conclusion // null)}')
            ;;
          *)
            status="PENDING"
            ;;
        esac
      fi
    fi

    # When (1) commit-status path ran, still merge issue-comment rate limits (P2: facts on GitHub must appear in JSON).
    if [ "$used_commit_status" = true ] && [ -n "$rate_limit_pat" ] && [ "$rate_limit_pat" != "null" ]; then
      local cs_arg
      cs_arg=$(echo "${cs_row_json:-null}" | jq -c '.')
      local rl_out
      rl_out=$(jq -nc \
        --argjson comments "$pr_comments" \
        --arg login_pat "$bot_login" \
        --arg match_type "$match_type" \
        --arg match_flags "$match_flags" \
        --arg rlpat "$rate_limit_pat" \
        --arg last_push "$last_push_at" \
        --argjson cs_row "$cs_arg" \
        --arg cur_status "$status" \
        '
        def ts($s):
          if $s == null or $s == "" then null else (try ($s | fromdateiso8601) catch null) end;
        ($last_push | ts(.)) as $tpush | (if $tpush == null then 0 else $tpush end) as $tp
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
        | if ($rlc | length) == 0 then {override: false, meta: null}
          else ($rlc | max_by(.created_at | ts(.))) as $best
          | ($best.created_at | ts(.)) as $rl_ts
          | (if ($cs_row | type) == "object" and ($cs_row.conclusion == "SUCCESS")
             then ($cs_row.completedAt // "" | ts(.)) else null end) as $cs_done_ts
          | (if $cur_status == "RATE_LIMITED" then false
            elif $cur_status == "PENDING" then true
            elif $cur_status == "COMPLETED" and $cs_done_ts != null then ($rl_ts > $cs_done_ts)
            elif $cur_status == "COMPLETED" then ($rl_ts >= $tp)
            else false
            end) as $ov
          | {override: $ov,
             meta: (if $ov then {detected: true, source: "issue_comment", detected_at: $best.created_at} else null end)}
          end
        ')
      _rl_meta=$(echo "$rl_out" | jq -c '.meta')
      if [ "$(echo "$rl_out" | jq -r '.override')" = "true" ]; then
        status="RATE_LIMITED"
        submitted=""
      fi
      if [ "$_rl_meta" != "null" ]; then
        rate_limit_meta="$_rl_meta"
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
      | (if ($rlc | length) == 0 then null else ($rlc | max_by(.created_at | ts(.))) end) as $best_rl
      | (if ($rlc | length) == 0 then null else ([$rlc[] | .created_at | ts(.)] | max) end) as $max_rl_ts
      | (if $latest_fresh == null then null else ($latest_fresh.submitted_at | ts(.)) end) as $max_rev_ts
      | if $latest_fresh != null and ($max_rl_ts == null or $max_rev_ts >= $max_rl_ts) then
          {status: "COMPLETED", submitted: $latest_fresh.submitted_at, rate_limit_meta: null}
        elif $max_rl_ts != null then
          {status: "RATE_LIMITED",
           submitted: (if $latest_fresh != null then $latest_fresh.submitted_at else null end),
           rate_limit_meta: (
             if $best_rl != null then {detected: true, source: "issue_comment", detected_at: $best_rl.created_at}
             else {detected: true, source: "issue_comment"}
             end
           )}
        else
          {status: "NOT_TRIGGERED", submitted: null, rate_limit_meta: null}
        end
      ')
      status=$(echo "$bot_status_json" | jq -r '.status')
      submitted=$(echo "$bot_status_json" | jq -r '.submitted // ""')
      if [ "$submitted" = "null" ]; then
        submitted=""
      fi
      rate_limit_meta=$(echo "$bot_status_json" | jq -c '.rate_limit_meta // null')
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

    # Bot-configured skip markers on PR issue comments (e.g. CodeRabbit "Review skipped")
    if [ "$status" != "REVIEW_INVALIDATED" ] && [ "$status" != "RATE_LIMITED" ]; then
      local skip_patterns_json skip_pol
      skip_patterns_json=$(echo "$bot_config" | jq -c ".bots[$i].skip_patterns // null")
      skip_pol=$(echo "$bot_config" | jq -r ".bots[$i].skip_policy // \"null\"")
      if [ "$skip_patterns_json" != "null" ] && [ "$(echo "$skip_patterns_json" | jq 'length')" -gt 0 ] && [ "$skip_pol" != "null" ]; then
        local skip_hit
        skip_hit=$(jq -nc \
          --argjson comments "$pr_comments" \
          --arg login_pat "$bot_login" \
          --arg match_type "$match_type" \
          --arg match_flags "$match_flags" \
          --arg lp "$last_push_at" \
          --argjson patterns "$skip_patterns_json" \
          '
          def ts($s):
            if $s == null or $s == "" then null else (try ($s | fromdateiso8601) catch null) end;
          ($lp | ts(.)) as $tpush | (if $tpush == null then 0 else $tpush end) as $tp
          | (if $match_type == "exact" then
              [ $comments[] | select(.user.login == $login_pat) ]
            elif ($match_flags != null and $match_flags != "") then
              [ $comments[] | select(.user.login | test($login_pat; $match_flags)) ]
            else
              [ $comments[] | select(.user.login | test($login_pat)) ]
            end) as $cand
          | ([ $cand[] | select((.created_at | ts(.)) != null and (.created_at | ts(.)) >= $tp) ]
            | sort_by(.created_at | ts(.))) as $sorted
          | (first(
              $sorted[] | . as $c | $patterns[] as $p
              | select(($c.body // "") | test($p))
              | {matched: true, reason: $p, at: $c.created_at}
            ) // {matched: false, reason: null, at: null})
          ')
        if [ "$(echo "$skip_hit" | jq -r '.matched')" = "true" ]; then
          skip_detected=true
          skip_reason=$(echo "$skip_hit" | jq -r '.reason')
          skip_detected_at=$(echo "$skip_hit" | jq -r '.at')
          case "$skip_pol" in
            terminal_clean)
              status="SKIPPED_CLEAN"
              submitted=""
              ;;
            terminal_blocked)
              status="SKIPPED_BLOCKED"
              submitted=""
              ;;
            *)
              ;;
          esac
        fi
      fi
    fi

    # Inline findings: top-level comments only, since head commit (ignore pre-push review noise)
    if [ "$match_type" = "exact" ]; then
      findings=$(echo "$cr_inline" | jq --arg login "$bot_login" --arg lp "$last_push_at" '
        def ts($s):
          if $s == null or $s == "" then null else (try ($s | fromdateiso8601) catch null) end;
        ($lp | ts(.)) as $tpush | (if $tpush == null then 0 else $tpush end) as $tp
        | [.[] | select(
            .user.login == $login
            and (.in_reply_to_id // null) == null
            and ((.created_at | ts(.)) != null and (.created_at | ts(.)) >= $tp)
          )]
        | length
      ')
    else
      if [ -n "$match_flags" ]; then
        findings=$(echo "$cr_inline" | jq --arg pat "$bot_login" --arg flags "$match_flags" --arg lp "$last_push_at" '
          def ts($s):
            if $s == null or $s == "" then null else (try ($s | fromdateiso8601) catch null) end;
          ($lp | ts(.)) as $tpush | (if $tpush == null then 0 else $tpush end) as $tp
          | [.[] | select(
              (.user.login | test($pat; $flags))
              and (.in_reply_to_id // null) == null
              and ((.created_at | ts(.)) != null and (.created_at | ts(.)) >= $tp)
            )]
          | length
        ')
      else
        findings=$(echo "$cr_inline" | jq --arg pat "$bot_login" --arg lp "$last_push_at" '
          def ts($s):
            if $s == null or $s == "" then null else (try ($s | fromdateiso8601) catch null) end;
          ($lp | ts(.)) as $tpush | (if $tpush == null then 0 else $tpush end) as $tp
          | [.[] | select(
              (.user.login | test($pat))
              and (.in_reply_to_id // null) == null
              and ((.created_at | ts(.)) != null and (.created_at | ts(.)) >= $tp)
            )]
          | length
        ')
      fi
    fi

    # Body-embedded "outside diff" counts: only reviews at or after head commit (ignore pre-push history)
    local body_count
    body_count=$(echo "$bot_reviews_all" | jq --arg lp "$last_push_at" '
      def ts($s):
        if $s == null or $s == "" then null else (try ($s | fromdateiso8601) catch null) end;
      ($lp | ts(.)) as $tpush | (if $tpush == null then 0 else $tpush end) as $tp
      | [.[] | select((.submitted_at | ts(.)) != null and (.submitted_at | ts(.)) >= $tp)
        | .body // ""
        | try (capture("Outside diff range comments \\((?<count>\\d+)\\)").count | tonumber) catch empty
      ] | add // 0
    ')
    findings=$((findings + body_count))

    # Compose bot entry
    local bot_entry skip_d_json
    if [ "$skip_detected" = true ]; then
      skip_d_json=true
    else
      skip_d_json=false
    fi
    bot_entry=$(jq -nc \
      --arg status "$status" \
      --arg sub "$submitted" \
      --argjson findings "$findings" \
      --argjson review_count "$review_count" \
      --argjson max_rev "$max_rev" \
      --argjson rate_limit "$rate_limit_meta" \
      --argjson skip_d "$skip_d_json" \
      --arg skip_r "${skip_reason:-}" \
      --arg skip_a "${skip_detected_at:-}" \
      '{
        "status": $status,
        "review_submitted_at": (if $sub == "" then null else $sub end),
        "findings_count": $findings,
        "review_count": $review_count,
        "max_reviews": $max_rev,
        "rate_limit": $rate_limit,
        "skip_detected": $skip_d,
        "skip_reason": (if $skip_r == "" then null else $skip_r end),
        "skip_detected_at": (if $skip_a == "" then null else $skip_a end)
      }')

    bot_json=$(echo "$bot_json" | jq -c --arg key "bot_$bot_id" --argjson val "$bot_entry" \
      '. + {($key): $val}')

    i=$((i + 1))
  done

  echo "$bot_json"
}

bot_reviews=$(_detect_bot_reviews)

# --- CodeRabbit re-review: latest @coderabbitai review issue comment vs answering pull review timestamp ---
# Pending when trigger is newer than any qualifying pull review (and review cap not reached). REVIEW_INVALIDATED clears pending.
coderabbit_status=$(echo "$bot_reviews" | jq -r '.bot_coderabbit.status // "NOT_TRIGGERED"')
coderabbit_submitted=$(echo "$bot_reviews" | jq -r '.bot_coderabbit.review_submitted_at // empty')
if [ "$coderabbit_submitted" = "null" ]; then
  coderabbit_submitted=""
fi
coderabbit_rc=$(echo "$bot_reviews" | jq '.bot_coderabbit.review_count // 0')
coderabbit_mx=$(echo "$bot_reviews" | jq -c 'if .bot_coderabbit.max_reviews == null then null else .bot_coderabbit.max_reviews end')
cr_skip_patterns=$(echo "$bot_config" | jq -c '[.bots[] | select(.id == "coderabbit")][0].skip_patterns // []')
re_review_signal=$(
  jq -nc \
    --argjson comments "$pr_comments" \
    --argjson revs "$reviews" \
    --argjson rc "$coderabbit_rc" \
    --argjson mx "$coderabbit_mx" \
    --argjson cr_skip_patterns "$cr_skip_patterns" \
    --arg cr_status "$coderabbit_status" \
    --arg cr_sub "$coderabbit_submitted" \
    '
    def ts($s):
      if $s == null or $s == "" then null else (try ($s | fromdateiso8601) catch null) end;
    ([ $comments[]
      | select((.body | ascii_downcase | contains("@coderabbitai")) and (.body | ascii_downcase | contains("review")))
      | select((.created_at | ts(.)) != null)
    ]) as $trig_comments
    | (if ($trig_comments | length) == 0 then null
       else ($trig_comments | max_by(.created_at | ts(.)) | .created_at)
       end) as $trig_at
    | ($trig_at | ts(.)) as $trig_ts
    | (if $trig_ts == null then null
       else
         ([ $revs[]
            | select(.user.login == "coderabbitai[bot]")
            | select((.submitted_at | ts(.)) != null and (.submitted_at | ts(.)) > $trig_ts)
          ]
          | if length == 0 then null
            else (max_by(.submitted_at | ts(.)) | .submitted_at)
            end)
       end) as $ans_rev
    | (if $trig_ts == null or $cr_sub == null or $cr_sub == "" then null
       elif (($cr_sub | ts(.)) != null and ($cr_sub | ts(.)) > $trig_ts) then $cr_sub
       else null
       end) as $ans_cs
    | (if $trig_ts == null or (($cr_skip_patterns | length) == 0) then null
       else
         ([ $comments[]
            | select(.user.login == "coderabbitai[bot]")
            | select((.created_at | ts(.)) != null and (.created_at | ts(.)) > $trig_ts)
           | select((.body // "") as $body
                    | any($cr_skip_patterns[]; $body | test(.)))
          ]
          | if length == 0 then null
            else (max_by(.created_at | ts(.)) | .created_at)
            end)
       end) as $ans_skip
    | ([$ans_rev, $ans_cs, $ans_skip] | map(select(. != null)) | sort_by(ts(.)) | last) as $ans_at
    | (if $cr_status == "REVIEW_INVALIDATED" then false
       elif ($cr_status == "SKIPPED_CLEAN" or $cr_status == "SKIPPED_BLOCKED") then false
       elif $trig_at == null then false
       elif $ans_at == null then true
       else false
       end) as $pend
    | (if ($mx != null) and ($rc >= $mx) then false else $pend end) as $pend2
    | ($trig_comments
      | sort_by(.created_at | ts(.)) | reverse
      | .[0:5]
      | map({created_at: .created_at, id: .id})
      ) as $trig_log
    | {
        latest_cr_trigger_created_at: $trig_at,
        latest_cr_review_submitted_at_after_trigger: $ans_at,
        latest_cr_skip_comment_at_after_trigger: $ans_skip,
        cr_response_pending_after_latest_trigger: $pend2,
        trigger_comment_log: $trig_log
      }
    '
)
rereview_pending_json=$(echo "$re_review_signal" | jq -c '.cr_response_pending_after_latest_trigger')

# --- Thread state ---
# shellcheck disable=SC2016
threads=$(gh api graphql -f query='
  query($owner: String!, $repo: String!, $pr: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $pr) {
        reviewThreads(first: 100) {
          totalCount
          pageInfo { hasNextPage }
          nodes { isResolved }
        }
      }
    }
  }
' -f owner="$owner" -f repo="$repo" -F pr="$PR" \
  --jq '{
    total: .data.repository.pullRequest.reviewThreads.totalCount,
    unresolved: [.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved | not)] | length,
    truncated: (.data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage // false)
  }' 2>/dev/null || echo '{"total":0,"unresolved":0,"truncated":true}')

threads_total=$(echo "$threads" | jq '.total')
threads_unresolved=$(echo "$threads" | jq '.unresolved')
review_threads_truncated=$(echo "$threads" | jq -c '.truncated // false')

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

# --- FSM merge-readiness + routing (jq module under docs/agent-control/fsm/pull-request-readiness.jq) ---
_fsm_dir="$(cd "$(dirname "$0")/.." && pwd)/docs/agent-control/fsm"
readiness=$(
  jq -nc \
    --argjson bots_map "$bot_reviews" \
    --argjson cfg "$bot_config" \
    --arg disposition "$disposition" \
    --argjson threads_u "$threads_unresolved" \
    --arg mergeable "$mergeable" \
    --arg merge_state "$merge_state" \
    --arg ci_status "$ci_status" \
    --argjson rereview_pending "$rereview_pending_json" \
    --argjson threads_truncated "$review_threads_truncated" \
    '{
      bots_map: $bots_map,
      bot_config: $cfg,
      disposition: $disposition,
      threads_unresolved: $threads_u,
      mergeable: $mergeable,
      merge_state: $merge_state,
      ci_status: $ci_status,
      rereview_response_pending: $rereview_pending,
      review_threads_truncated: $threads_truncated
    }' | jq -f "$_fsm_dir/pull-request-readiness.jq"
)
review_diagnostics=$(echo "$readiness" | jq -c '.diagnostics')
routing_pr=$(echo "$readiness" | jq -c '.routing')
auto_merge_readiness=$(echo "$readiness" | jq -c '.auto_merge_readiness')

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
  --argjson review_threads_truncated "$review_threads_truncated" \
  --arg disposition "$disposition" \
  --arg last_review "$last_review_at" \
  --arg last_push "$last_push_at" \
  --argjson closes "$closes_issues" \
  --argjson has_exc "$has_exception" \
  --argjson exc_type "$exception_type" \
  --argjson routing_pr "$routing_pr" \
  --argjson auto_merge_readiness "$auto_merge_readiness" \
  --argjson review_diagnostics "$review_diagnostics" \
  --argjson re_review_signal "$re_review_signal" \
  '{
    "number": $number,
    "title": $title,
    "state": $state,
    "head_branch": $head,
    "base_branch": $base,
    "routing": $routing_pr,
    "auto_merge_readiness": $auto_merge_readiness,
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
        "review_threads_truncated": $review_threads_truncated,
        "disposition": $disposition,
        "last_review_at": (if $last_review == "" then null else $last_review end),
        "last_push_at": $last_push,
        "diagnostics": $review_diagnostics,
        "re_review_signal": $re_review_signal
      }
    ),
    "traceability": {
      "closes_issues": $closes,
      "has_exception_label": $has_exc,
      "exception_type": $exc_type
    }
  }')

evidence_emit "$body"
