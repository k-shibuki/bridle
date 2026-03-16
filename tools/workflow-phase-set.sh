#!/usr/bin/env bash
# tools/workflow-phase-set.sh -- Persist workflow phase for FSM classification
# Usage: bash tools/workflow-phase-set.sh <phase> [--issue N] [--branch name]
#        bash tools/workflow-phase-set.sh --clear
set -euo pipefail

STATE_DIR=".cursor/state"
STATE_FILE="$STATE_DIR/workflow-phase.json"

VALID_PHASES="implementing implementation_done tests_done quality_ok tests_pass"

_usage() {
  echo "Usage: $0 <phase> [--issue N] [--branch name]"
  echo "       $0 --clear"
  echo "Phases: $VALID_PHASES"
  exit 1
}

if [ "${1:-}" = "--clear" ]; then
  rm -f "$STATE_FILE"
  exit 0
fi

phase="${1:-}"
if [ -z "$phase" ]; then
  _usage
fi

valid=false
for p in $VALID_PHASES; do
  [ "$phase" = "$p" ] && valid=true
done
if [ "$valid" = "false" ]; then
  echo "ERROR: invalid phase '$phase'. Must be one of: $VALID_PHASES" >&2
  exit 1
fi

shift
issue=""
branch=""

while [ $# -gt 0 ]; do
  case "$1" in
    --issue) issue="$2"; shift 2 ;;
    --branch) branch="$2"; shift 2 ;;
    *) echo "ERROR: unknown option '$1'" >&2; _usage ;;
  esac
done

if [ -z "$branch" ]; then
  branch=$(git branch --show-current 2>/dev/null || echo "")
fi

mkdir -p "$STATE_DIR"

now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

jq -nc \
  --arg phase "$phase" \
  --arg issue "$issue" \
  --arg branch "$branch" \
  --arg updated_at "$now" \
  '{
    "workflow_phase": $phase,
    "issue_number": (if $issue == "" then null else ($issue | tonumber) end),
    "branch": $branch,
    "updated_at": $updated_at
  }' > "$STATE_FILE"
