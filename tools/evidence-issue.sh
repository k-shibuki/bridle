#!/usr/bin/env bash
# tools/evidence-issue.sh -- Issue metadata for prioritization
# Optional ISSUE= argument for single-issue mode.
# Network access: GitHub REST API
set -euo pipefail
. "$(dirname "$0")/evidence-lib.sh"

evidence_init "evidence-issue"

ISSUE="${ISSUE:-}"

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
  has_test_plan: ((.body // "") | test("## Test Plan"; "i")),
  has_acceptance_criteria: ((.body // "") | test("## (Acceptance Criteria|Definition of Done)"; "i")),
  blocked_by: [(.body // "") | capture("(?:Depends on|Blocked by|After)[^\\n]*#(?<n>\\d+)"; "g") | .n | tonumber] | unique,
  blocks: [(.body // "") | capture("(?:Blocks|Enables|Before)[^\\n]*#(?<n>\\d+)"; "g") | .n | tonumber] | unique,
  is_parent: ((.body // "") | test("## Sub-issues"; "i")),
  assignee: ((.assignees // [])[0].login // null),
  created_at: .createdAt
}]')

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
