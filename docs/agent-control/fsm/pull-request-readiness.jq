# Input: {
#   bots_map, bot_config, disposition, threads_unresolved, mergeable, merge_state, ci_status,
#   rereview_response_pending (optional boolean, default false),
#   review_threads_truncated (optional boolean, default false) — GraphQL reviewThreads(first:100) hasNextPage
# }
# Output: { diagnostics, auto_merge_readiness, routing }

def reviewed($s):
  $s == "COMPLETED" or $s == "COMPLETED_CLEAN" or $s == "COMPLETED_SILENT";

def failed($s):
  $s == "RATE_LIMITED" or $s == "TIMED_OUT";

def rows($bots_map; $cfg):
  [ $cfg.bots[] | . as $b
    | ($bots_map["bot_\($b.id)"] // {}) as $row
    | {
        required: $b.required,
        status: ($row.status // "NOT_TRIGGERED"),
        findings: ($row.findings_count // 0),
        review_count: ($row.review_count // 0),
        max_reviews: $b.max_reviews
      }
  ];

def required_bot_done($r):
  reviewed($r.status)
  or ($r.status == "NOT_TRIGGERED" and ($r.max_reviews != null) and ($r.review_count >= $r.max_reviews));

def required_findings_total($rows):
  [ $rows[] | select(.required) | .findings ] | add // 0;

def bot_review_completed($rows):
  ($rows | all(
    if .required then required_bot_done(.)
    else (reviewed(.status) or (.status == "NOT_TRIGGERED"))
    end
  ));

def bot_review_failed($rows):
  ($rows | any(.required and failed(.status)));

def bot_review_terminal($rows):
  (bot_review_failed($rows)) or (bot_review_completed($rows));

def bot_review_pending($rows):
  (bot_review_terminal($rows) | not);

def review_consensus_complete($rows; $disposition; $threads_u; $pending; $threads_truncated):
  ($disposition == "approved")
  or (
    $disposition == "pending"
    and ($pending | not)
    and $threads_u == 0
    and ($threads_truncated | not)
    and (required_findings_total($rows) == 0)
    and ($rows | all(
      if .required then required_bot_done(.)
      else (reviewed(.status) or (.status == "NOT_TRIGGERED"))
      end
    ))
  );

def blockers($rows; $disposition; $threads_u; $mergeable; $merge_state; $ci_status; $pending; $threads_truncated):
  []
  | (if $ci_status != "success" then . + ["ci_not_green"] else . end)
  | (if $mergeable != "MERGEABLE" then . + ["merge_not_mergeable"] else . end)
  | (if $merge_state == "BEHIND" then . + ["base_branch_behind"] else . end)
  | (if ($merge_state != "CLEAN" and $merge_state != "HAS_HOOKS" and $merge_state != "UNKNOWN" and $merge_state != "BEHIND")
     then . + ["merge_state_blocked"] else . end)
  | (if $threads_u > 0 then . + ["unresolved_threads"] else . end)
  | (if $disposition == "changes_requested" then . + ["changes_requested"] else . end)
  | (if ($rows | any(
        .required
        and (
          .status == "REVIEW_INVALIDATED"
          or .status == "PENDING"
          or (
            .status == "NOT_TRIGGERED"
            and ((.max_reviews == null) or (.review_count < .max_reviews))
          )
        )
      ))
     then . + ["required_bot_rereview"] else . end)
  | (if (required_findings_total($rows) > 0) and ($disposition != "approved") then . + ["required_bot_findings"] else . end)
  | (if $pending and $threads_u == 0 then . + ["rereview_response_pending"] else . end)
  | (if ($rows | any(.required and (.status == "RATE_LIMITED" or .status == "TIMED_OUT")))
     then . + ["bot_rate_limited"] else . end)
  | (if $threads_truncated then . + ["review_threads_truncated"] else . end);

def pr_state_id($rows; $disposition; $threads_u; $mergeable; $merge_state; $ci_status; $pending; $threads_truncated):
  if $ci_status == "failure" then "CIFailed"
  elif $mergeable == "CONFLICTING" then "DependentChainRebase"
  elif $threads_u > 0 then "UnresolvedThreads"
  elif $disposition == "changes_requested" then "ChangesRequired"
  elif (required_findings_total($rows) > 0) and ($disposition != "approved") then "UnresolvedThreads"
  elif $threads_truncated then "UnresolvedThreads"
  elif ($ci_status == "pending" or $ci_status == "no_checks") then "CIPending"
  elif $ci_status == "success" and $pending then "BotReviewPending"
  elif $ci_status == "success" and (bot_review_pending($rows)) then "BotReviewPending"
  elif $ci_status == "success"
       and (review_consensus_complete($rows; $disposition; $threads_u; $pending; $threads_truncated))
       and $mergeable == "MERGEABLE"
       and ($merge_state == "CLEAN" or $merge_state == "HAS_HOOKS")
    then "ReviewDone"
  elif $ci_status == "success" and (bot_review_terminal($rows)) and $threads_u == 0
       and (review_consensus_complete($rows; $disposition; $threads_u; $pending; $threads_truncated) | not)
    then "ReadyForReview"
  elif $ci_status == "success" then "ReadyForReview"
  else "CIPending"
  end;

  . as $in
  | (rows($in.bots_map; $in.bot_config)) as $rows
  | ($in.disposition) as $d
  | ($in.threads_unresolved // 0) as $tu
  | ($in.mergeable) as $m
  | ($in.merge_state) as $ms
  | ($in.ci_status) as $cs
  | ($in.rereview_response_pending // false) as $pend
  | ($in.review_threads_truncated // false) as $tt
  | {
      diagnostics: {
        bot_review_completed: bot_review_completed($rows),
        bot_review_failed: bot_review_failed($rows),
        bot_review_terminal: bot_review_terminal($rows),
        bot_review_pending: bot_review_pending($rows),
        required_bot_findings_total: required_findings_total($rows),
        required_bot_findings_outstanding: ((required_findings_total($rows)) > 0),
        non_thread_bot_findings_outstanding: ((required_findings_total($rows) > 0) and ($tu == 0)),
        rereview_response_pending: $pend,
        required_bot_rate_limited: ($rows | any(.required and .status == "RATE_LIMITED")),
        required_bot_timed_out: ($rows | any(.required and .status == "TIMED_OUT"))
      },
      auto_merge_readiness: (
        (blockers($rows; $d; $tu; $m; $ms; $cs; $pend; $tt)) as $bl
        | {
            review_consensus_complete: review_consensus_complete($rows; $d; $tu; $pend; $tt),
            ci_all_required_passed: ($cs == "success"),
            blockers: $bl
          }
        | .safe_to_enable =
            (.review_consensus_complete
             and .ci_all_required_passed
             and ($m == "MERGEABLE")
             and ($ms == "CLEAN" or $ms == "HAS_HOOKS")
             and (.blockers | length == 0))
      ),
      routing: {
        pr_state_id: pr_state_id($rows; $d; $tu; $m; $ms; $cs; $pend; $tt)
      }
    }
