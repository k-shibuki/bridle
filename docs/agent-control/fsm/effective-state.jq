# Build evidence-fsm aggregate document.
# --argjson wp: workflow_position (with routing.global_state_id)
# --argjson environment: evidence-environment body (no _meta)
# --argjson issues_summary: evidence-issue body or null
# --argjson pull_request: evidence-pull-request body or null

def prio($s):
  if $s == "EnvironmentIssue" then 1
  elif $s == "CIFailed" then 2
  elif $s == "DependentChainRebase" then 3
  elif $s == "UnresolvedThreads" then 4
  elif $s == "ChangesRequired" then 5
  elif $s == "StaleBranches" then 6
  elif $s == "CIPending" then 7
  elif $s == "BotReviewPending" then 8
  elif $s == "ReadyForReview" then 9
  elif $s == "ReviewDone" then 10
  elif $s == "NoWorkPlanned" then 11
  elif $s == "PreFlightReview" then 12
  elif $s == "ReadyToStart" then 13
  elif $s == "ExceptionFlow" then 14
  elif $s == "CycleComplete" then 15
  elif $s == "Implementing" then 20
  elif $s == "ImplementationDone" then 21
  elif $s == "TestsDone" then 22
  elif $s == "QualityOK" then 23
  elif $s == "TestsPass" then 24
  elif $s == "Committed" then 25
  else 99
  end;

def pick_effective($g; $p):
  if $p == null then $g
  elif $g == null then $p
  elif prio($g) < prio($p) then $g
  elif prio($p) < prio($g) then $p
  else $g
  end;

$wp as $workflow
| $environment as $envj
| $issues_summary as $issj
| ($pull_request // null) as $pull
| ($workflow.routing.global_state_id) as $gid
| (if $pull != null then $pull.routing.pr_state_id else null end) as $pid
| {
    workflow_position: $workflow,
    environment: $envj,
    issues_summary: $issj,
    pull_request: $pull,
    routing: {
      effective_state_id: pick_effective($gid; $pid),
      global_state_id: $gid,
      pr_state_id: $pid,
      recommended_next_issue: null
    }
  }
