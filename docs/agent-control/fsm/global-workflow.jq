# Workflow-position partial FSM: add routing.global_state_id (SSOT for global mode).
# Input: evidence-workflow-position body (without routing).
# --argjson env_errors: integer; use 0 when environment errors unknown.
# EnvironmentIssue also when environment.container_running == false (strict boolean).

def preflight_needed($open):
  ($open | length > 0) and ($open | any(
    (.has_test_plan | not) or (.has_acceptance_criteria | not)
  ));

def pr_for_branch($branch; $prs):
  ([$prs.open[] | select(.head_branch == $branch)] | first) // null;

. as $wp
| ($wp.git) as $g
| ($wp.issues) as $is
| ($wp.pull_requests) as $prs
| ($wp.procedure_context) as $ctx
| (pr_for_branch($g.branch; $prs)) as $pr
| (if $env_errors > 0 then "EnvironmentIssue"
  elif ($wp.environment.container_running == false) then "EnvironmentIssue"
  elif ($g.stale_branches | length) > 0 then "StaleBranches"
  elif $is.open_count == 0 then "NoWorkPlanned"
  elif $g.on_main and ($g.uncommitted_files == 0) and preflight_needed($is.open) then "PreFlightReview"
  elif $g.on_main and ($g.uncommitted_files == 0) and (preflight_needed($is.open) | not) then "ReadyToStart"
  elif ($g.on_main | not) and ($pr != null) then
      if $pr.ci_status == "failure" then "CIFailed"
      elif $pr.mergeable == "CONFLICTING" then "DependentChainRebase"
      elif ($pr.review_threads_unresolved // 0) > 0 then "UnresolvedThreads"
      elif ($pr.ci_status == "pending" or $pr.ci_status == "no_checks") then "CIPending"
      elif $pr.ci_status == "success" then "BotReviewPending"
      else "CIPending"
      end
  elif ($g.on_main | not) and ($g.uncommitted_files > 0) then
      ($ctx.workflow_phase // "") as $ph
      | if $ph == "implementation_done" then "ImplementationDone"
        elif $ph == "tests_done" then "TestsDone"
        elif $ph == "quality_ok" then "QualityOK"
        elif $ph == "tests_pass" then "TestsPass"
        elif $ph == "implementing" then "Implementing"
        else "Implementing"
        end
  elif ($g.on_main | not) and ($g.uncommitted_files == 0) and ($pr == null) then "Committed"
  elif $g.on_main then "ReadyToStart"
  else "ReadyToStart"
  end) as $gid
| $wp + {routing: {global_state_id: $gid}}
