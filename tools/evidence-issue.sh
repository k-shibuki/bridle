#!/usr/bin/env bash
# tools/evidence-issue.sh -- Issue metadata for prioritization
# Optional ISSUE= argument for single-issue mode.
# Network access: GitHub REST API
set -euo pipefail
# shellcheck disable=SC1091 source=evidence-lib.sh
. "$(dirname "$0")/evidence-lib.sh"

evidence_init "evidence-issue"

ISSUE="${ISSUE:-}"
SCOPE="${SCOPE:-}"
ISSUE_MIN="${ISSUE_MIN:-}"

if ! command -v gh >/dev/null 2>&1; then
  evidence_error "gh" "gh CLI not found" true
  evidence_emit '{}'
  exit 0
fi

if [ -n "$ISSUE" ]; then
  raw=$(gh issue view "$ISSUE" --json number,title,labels,body,assignees,createdAt 2>/dev/null || echo "")
  if [ -z "$raw" ]; then
    evidence_error "gh issue view" "Issue #$ISSUE not found" true
    evidence_emit '{}'
    exit 0
  fi
  raw="[$raw]"
else
  raw=$(gh issue list --state open --json number,title,labels,body,assignees,createdAt --limit 50 2>/dev/null || echo "[]")
fi

issues=$(echo "$raw" | jq -c '[.[] | {
  number: .number,
  title: .title,
  labels: [(.labels // [])[] | .name],
  body: (.body // ""),
  has_test_plan: (
    if [(.labels // [])[] | .name] | any(. == "has-test-plan") then true
    else ((.body // "") | test("## Test Plan"; "i"))
    end
  ),
  has_acceptance_criteria: (
    if [(.labels // [])[] | .name] | any(. == "has-acceptance-criteria") then true
    else ((.body // "") | test("## (Acceptance Criteria|Definition of Done)"; "i"))
    end
  ),
  blocked_by: [(.body // "") | capture("(?:Depends on|Blocked by|After)[^\\n]*?#(?<n>\\d+)"; "g") | .n | tonumber] | unique,
  blocks: [(.body // "") | capture("(?:Blocks|Enables|Before)[^\\n]*?#(?<n>\\d+)"; "g") | .n | tonumber] | unique,
  is_parent: ((.body // "") | test("## Sub-issues"; "i")),
  assignee: ((.assignees // [])[0].login // null),
  created_at: .createdAt
}]')

# Optional scope filter: control-system (label agent-control or number >= ISSUE_MIN) or ISSUE_MIN only
if [ -n "$SCOPE" ] || [ -n "$ISSUE_MIN" ]; then
  if [ "$SCOPE" = "control-system" ]; then
    min="${ISSUE_MIN:-252}"
    issues=$(echo "$issues" | jq -c --argjson min "$min" '[.[] | select((.labels | index("agent-control")) or (.number >= $min))]')
  elif [ -n "$ISSUE_MIN" ]; then
    issues=$(echo "$issues" | jq -c --argjson min "$ISSUE_MIN" '[.[] | select(.number >= $min)]')
  fi
fi

# Enrich parent issues: child_issues, children_closed, parent_closeable (Plan §7; state via gh, not checkbox)
SCRIPT_DIR="$(dirname "$0")"
enriched='['
first=true
while read -r issue; do
  is_parent=$(echo "$issue" | jq -r '.is_parent')
  if [ "$is_parent" != "true" ]; then
    issue=$(echo "$issue" | jq -c '. + {child_issues: [], children_closed: true, parent_closeable: false}')
  else
    body=$(echo "$issue" | jq -r '.body')
    child_issues=$(echo "$body" | bash "$SCRIPT_DIR/parse-sub-issues.sh")
    children_closed="true"
    for n in $(echo "$child_issues" | jq -r '.[]'); do
      state=$(gh issue view "$n" --json state -q .state 2>/dev/null || echo "OPEN")
      if [ "$state" != "CLOSED" ]; then children_closed="false"; fi
    done
    issue=$(echo "$issue" | jq -c --argjson child "$child_issues" \
      --argjson closed "$children_closed" \
      '. + {child_issues: $child, children_closed: $closed, parent_closeable: $closed}')
  fi
  if [ "$first" = true ]; then first=false; else enriched="$enriched,"; fi
  enriched="$enriched$issue"
done < <(echo "$issues" | jq -c '.[]')
enriched="$enriched]"
issues="$enriched"

roots=$(echo "$issues" | jq -c '[.[] | select((.blocked_by | length) == 0) | .number]')

all_blocking=$(echo "$issues" | jq -c '[.[].blocked_by[]] | unique')
leaves=$(echo "$issues" | jq -c --argjson blockers "$all_blocking" \
  '[.[] | select(.number as $n | ($blockers | index($n)) == null) | .number]')

depth=$(echo "$issues" | jq '
  . as $all |
  def find_depth($num; $visited):
    if ($visited | index($num)) then 0
    else
      ($all | map(select(.number == $num)) | .[0].blocked_by // []) as $deps |
      if ($deps | length) == 0 then 0
      else 1 + ([$deps[] | find_depth(.; $visited + [$num])] | max)
      end
    end;
  if length == 0 then 0
  else [.[].number as $n | find_depth($n; [])] | max // 0
  end
')

body=$(jq -nc \
  --argjson issues "$issues" \
  --argjson roots "$roots" \
  --argjson leaves "$leaves" \
  --argjson depth "$depth" \
  '{
    "issues": $issues,
    "dependency_graph": {
      "roots": $roots,
      "leaves": $leaves,
      "depth": $depth
    }
  }')

evidence_emit "$body"
