# Input: evidence-fsm body from effective-state.jq (before this step).
# --arg current_user: GitHub login from `gh api user` (empty string if unknown).
# Sets .routing.recommended_next_issue to a number or null.
# Rules: workflow--issue-selection.md (actionability + ranking).

def open_numbers($issues):
  [ $issues[] | .number ];

def is_exception($labels):
  (($labels | index("hotfix")) != null) or (($labels | index("no-issue")) != null);

def blocked_by_open($blocked_by; $open_nums):
  any($blocked_by[]?; . as $b | ($open_nums | index($b) != null));

def priority_rank($labels):
  if ($labels | index("high")) != null then 0
  elif ($labels | index("medium")) != null then 1
  elif ($labels | index("low")) != null then 2
  else 3
  end;

def assignee_ok($assignee; $user):
  ($assignee == null) or ($user != "" and $assignee == $user);

def actionable($issue; $open_nums; $user):
  ($issue.is_parent | not)
  and ($issue.has_test_plan)
  and ($issue.has_acceptance_criteria)
  and assignee_ok($issue.assignee; $user)
  and (is_exception($issue.labels) | not)
  and (blocked_by_open($issue.blocked_by // []; $open_nums) | not);

def blocks_len($issue):
  ($issue.blocks // []) | length;

. as $root
| ($root.workflow_position.git.on_main) as $on_main
| ($root.issues_summary) as $isum
| ($root.routing) as $rout
| (
    if ($on_main | not) or ($isum == null) or (($isum.issues // []) | length) == 0 then null
    else
      ($isum.issues) as $issues
      | open_numbers($issues) as $open_nums
      | [ $issues[] | select(actionable(.; $open_nums; $current_user)) ] as $cand
      | if ($cand | length) == 0 then null
        else
          $cand
          | sort_by([
              priority_rank(.labels),
              -(blocks_len(.)),
              ((.blocked_by // []) | length),
              (.created_at // "")
            ])
          | .[0].number
        end
    end
  ) as $rec
| $root
| .routing = ($rout + {recommended_next_issue: $rec})
