#!/usr/bin/env bash
# Offline jq regression tests for FSM policy (docs/agent-control/fsm/).
# Usage: bash tools/test-fsm-fixtures.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FSM="$ROOT/docs/agent-control/fsm"
BOT_CFG="$ROOT/docs/agent-control/review-bots.json"
# Optional override for testthat (single directory of case JSON files)
CASE_DIR="${BRIDLE_TEST_FSM_CASE_DIR:-$ROOT/tests/evidence/golden/fsm/cases}"

if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL: jq is required" >&2
  exit 1
fi

if [ ! -f "$BOT_CFG" ]; then
  echo "FAIL: missing $BOT_CFG" >&2
  exit 1
fi

bot_config_json=$(jq -c '.' "$BOT_CFG")
errors=0
fixtures_ran=0

run_pr_readiness() {
  local file="$1"
  local id result
  id=$(jq -r '.id' "$file")
  result=$(
    jq -n \
      --argjson inp "$(jq -c '.input' "$file")" \
      --argjson cfg "$bot_config_json" \
      '$inp + {bot_config: $cfg}' |
      jq -f "$FSM/pull-request-readiness.jq"
  )

  local exp_cc exp_safe exp_pid
  exp_cc=$(jq -r '.expect.review_consensus_complete' "$file")
  exp_safe=$(jq -r '.expect.safe_to_enable' "$file")
  exp_pid=$(jq -r '.expect.pr_state_id // empty' "$file")

  local got_cc got_safe got_pid
  got_cc=$(echo "$result" | jq -c '.auto_merge_readiness.review_consensus_complete')
  got_safe=$(echo "$result" | jq -c '.auto_merge_readiness.safe_to_enable')
  got_pid=$(echo "$result" | jq -r '.routing.pr_state_id')

  if [ "$got_cc" != "$exp_cc" ]; then
    echo "FAIL [$id] review_consensus_complete: got $got_cc expected $exp_cc" >&2
    echo "$result" | jq . >&2
    errors=$((errors + 1))
    return
  fi
  if [ "$got_safe" != "$exp_safe" ]; then
    echo "FAIL [$id] safe_to_enable: got $got_safe expected $exp_safe" >&2
    echo "$result" | jq . >&2
    errors=$((errors + 1))
    return
  fi
  if [ -n "$exp_pid" ] && [ "$got_pid" != "$exp_pid" ]; then
    echo "FAIL [$id] pr_state_id: got $got_pid expected $exp_pid" >&2
    echo "$result" | jq . >&2
    errors=$((errors + 1))
    return
  fi

  while IFS= read -r code; do
    [ -z "$code" ] && continue
    if ! echo "$result" | jq -e --arg c "$code" '.auto_merge_readiness.blockers | contains([$c])' >/dev/null 2>&1; then
      echo "FAIL [$id] blockers missing code: $code (got $(echo "$result" | jq -c '.auto_merge_readiness.blockers'))" >&2
      errors=$((errors + 1))
      return
    fi
  done < <(jq -r '.expect.blockers_contains[]? // empty' "$file")

  local exp_empty
  exp_empty=$(jq -r '.expect.blockers_empty // false' "$file")
  if [ "$exp_empty" = "true" ]; then
    local blen
    blen=$(echo "$result" | jq '.auto_merge_readiness.blockers | length')
    if [ "$blen" != "0" ]; then
      echo "FAIL [$id] expected empty blockers, got length $blen" >&2
      errors=$((errors + 1))
      return
    fi
  fi

  echo "OK [$id] pull_request_readiness"
}

run_effective_state() {
  local file="$1"
  local id exp eff
  id=$(jq -r '.id' "$file")
  exp=$(jq -r '.expect.effective_state_id' "$file")
  eff=$(
    jq -n \
      --argjson wp "$(jq -c '.input.workflow_position' "$file")" \
      --argjson environment "$(jq -c '.input.environment' "$file")" \
      --argjson issues_summary "$(jq -c '.input.issues_summary' "$file")" \
      --argjson pull_request "$(jq -c '.input.pull_request' "$file")" \
      -f "$FSM/effective-state.jq" |
      jq -r '.routing.effective_state_id'
  )
  if [ "$eff" != "$exp" ]; then
    echo "FAIL [$id] effective_state_id: got $eff expected $exp" >&2
    errors=$((errors + 1))
    return
  fi
  echo "OK [$id] effective_state"
}

run_global_workflow() {
  local file="$1"
  local id exp got
  id=$(jq -r '.id' "$file")
  exp=$(jq -r '.expect.global_state_id' "$file")
  local env_err
  env_err=$(jq -r '.input.env_errors // 0' "$file")
  got=$(
    jq -c '.input.workflow_body' "$file" |
      jq -c --argjson env_errors "$env_err" -f "$FSM/global-workflow.jq" |
      jq -r '.routing.global_state_id'
  )
  if [ "$got" != "$exp" ]; then
    echo "FAIL [$id] global_state_id: got $got expected $exp" >&2
    errors=$((errors + 1))
    return
  fi
  echo "OK [$id] global_workflow"
}

run_augment_routing() {
  local file="$1"
  local id base exp_rec got_rec
  id=$(jq -r '.id' "$file")
  base=$(jq -c '.input.base_fsm' "$file")
  exp_rec=$(jq -c '.expect.recommended_next_issue' "$file")
  got_rec=$(
    echo "$base" | jq -c --arg current_user "$(jq -r '.input.current_user // ""' "$file")" -f "$FSM/augment-routing.jq" |
      jq -c '.routing.recommended_next_issue'
  )
  if [ "$got_rec" != "$exp_rec" ]; then
    echo "FAIL [$id] recommended_next_issue: got $got_rec expected $exp_rec" >&2
    errors=$((errors + 1))
    return
  fi
  echo "OK [$id] augment_routing"
}

if [ ! -d "$CASE_DIR" ]; then
  echo "FAIL: case directory missing: $CASE_DIR" >&2
  exit 1
fi

shopt -s nullglob
for f in "$CASE_DIR"/*.json; do
  fixtures_ran=$((fixtures_ran + 1))
  kind=$(jq -r '.kind' "$f")
  case "$kind" in
    pull_request_readiness) run_pr_readiness "$f" ;;
    effective_state) run_effective_state "$f" ;;
    global_workflow) run_global_workflow "$f" ;;
    augment_routing) run_augment_routing "$f" ;;
    *)
      echo "FAIL: unknown kind '$kind' in $f" >&2
      errors=$((errors + 1))
      ;;
  esac
done
shopt -u nullglob

if [ "$fixtures_ran" -eq 0 ]; then
  echo "FAIL: no fixture JSON files in $CASE_DIR" >&2
  exit 1
fi

if [ "$errors" -gt 0 ]; then
  echo "FAIL: $errors fixture error(s)" >&2
  exit 1
fi

echo "OK: all FSM fixtures passed"
