#!/usr/bin/env bash
# tools/evidence-fsm.sh -- Unified FSM evidence (Refs: #282)
# Collection order: evidence-environment → evidence-workflow-position (recompute global with env errors)
# → (on main with open issues) evidence-issue → (if open PR for current branch) evidence-pull-request
set -euo pipefail
# shellcheck disable=SC1091 source=evidence-lib.sh
. "$(dirname "$0")/evidence-lib.sh"

evidence_init "evidence-fsm"

_fsm_dir="$(cd "$(dirname "$0")/.." && pwd)/docs/agent-control/fsm"

env_raw=$(bash "$(dirname "$0")/evidence-environment.sh")
wp_raw=$(bash "$(dirname "$0")/evidence-workflow-position.sh")

env_json=$(echo "$env_raw" | jq 'del(._meta)')
wp_json=$(echo "$wp_raw" | jq 'del(._meta)')
env_errors=$(echo "$env_json" | jq '.errors // 0')

wp_core=$(echo "$wp_json" | jq 'del(.routing)')
wp_fixed=$(echo "$wp_core" | jq -c --argjson env_errors "$env_errors" -f "$_fsm_dir/global-workflow.jq")

branch=$(echo "$wp_fixed" | jq -r '.git.branch')
pr_json="null"
if command -v gh >/dev/null 2>&1; then
  pr_num=$(gh pr list --head "$branch" --json number -q '.[0].number' 2>/dev/null || echo "")
  if [ -n "$pr_num" ] && [ "$pr_num" != "null" ]; then
    pr_raw=$(PR="$pr_num" bash "$(dirname "$0")/evidence-pull-request.sh")
    pr_json=$(echo "$pr_raw" | jq 'del(._meta)')
  fi
fi

issues_json="null"
if command -v gh >/dev/null 2>&1; then
  on_main=$(echo "$wp_fixed" | jq -r '.git.on_main')
  oc=$(echo "$wp_fixed" | jq '.issues.open_count')
  if [ "$on_main" = "true" ] && [ "${oc:-0}" -gt 0 ] 2>/dev/null; then
    iss_raw=$(bash "$(dirname "$0")/evidence-issue.sh")
    issues_json=$(echo "$iss_raw" | jq 'del(._meta)')
  fi
fi

body=$(jq -n \
  --argjson wp "$wp_fixed" \
  --argjson environment "$env_json" \
  --argjson issues_summary "$issues_json" \
  --argjson pull_request "$pr_json" \
  -f "$_fsm_dir/effective-state.jq")

current_user=""
if command -v gh >/dev/null 2>&1; then
  current_user=$(gh api user -q .login 2>/dev/null || echo "")
fi

body=$(echo "$body" | jq -c --arg current_user "$current_user" -f "$_fsm_dir/augment-routing.jq")

evidence_emit "$body"
