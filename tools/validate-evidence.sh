#!/usr/bin/env bash
# tools/validate-evidence.sh -- Validate evidence target output structure
# Usage: bash tools/validate-evidence.sh [TARGET_NAME]
# Without argument, validates all golden examples in tests/evidence/golden/
set -euo pipefail

GOLDEN_DIR="tests/evidence/golden"
errors=0

validate_json() {
  local file="$1" target="$2"
  local json

  if ! json=$(cat "$file" 2>/dev/null); then
    echo "FAIL [$target]: cannot read $file" >&2
    return 1
  fi

  # Must be valid JSON
  if ! echo "$json" | jq . >/dev/null 2>&1; then
    echo "FAIL [$target]: invalid JSON" >&2
    return 1
  fi

  # Must have _meta envelope
  if ! echo "$json" | jq -e '._meta' >/dev/null 2>&1; then
    echo "FAIL [$target]: missing _meta envelope" >&2
    return 1
  fi

  # _meta must have required fields
  for field in target timestamp version duration_ms; do
    if ! echo "$json" | jq -e "._meta.$field" >/dev/null 2>&1; then
      echo "FAIL [$target]: _meta missing field '$field'" >&2
      return 1
    fi
  done

  # _meta.target must match expected
  actual_target=$(echo "$json" | jq -r '._meta.target')
  if [ "$actual_target" != "$target" ]; then
    echo "FAIL [$target]: _meta.target is '$actual_target', expected '$target'" >&2
    return 1
  fi

  # Validate target-specific required top-level keys
  # Use has() instead of -e to handle boolean false and zero values correctly
  case "$target" in
    evidence-workflow-position)
      for key in git issues pull_requests environment procedure_context routing; do
        if ! echo "$json" | jq -e "has(\"$key\")" >/dev/null 2>&1; then
          echo "FAIL [$target]: missing required key '$key'" >&2
          return 1
        fi
      done
      ;;
    evidence-environment)
      for key in errors warnings runtime checks; do
        if ! echo "$json" | jq -e "has(\"$key\")" >/dev/null 2>&1; then
          echo "FAIL [$target]: missing required key '$key'" >&2
          return 1
        fi
      done
      ;;
    evidence-lint)
      for key in file_count finding_count findings; do
        if ! echo "$json" | jq -e "has(\"$key\")" >/dev/null 2>&1; then
          echo "FAIL [$target]: missing required key '$key'" >&2
          return 1
        fi
      done
      ;;
    evidence-pull-request)
      for key in number title routing auto_merge_readiness ci merge reviews traceability; do
        if ! echo "$json" | jq -e "has(\"$key\")" >/dev/null 2>&1; then
          echo "FAIL [$target]: missing required key '$key'" >&2
          return 1
        fi
      done
      if ! echo "$json" | jq -e '.routing | has("pr_state_id") and (.pr_state_id | type == "string")' >/dev/null 2>&1; then
        echo "FAIL [$target]: routing.pr_state_id missing or not a string" >&2
        return 1
      fi
      for amk in review_consensus_complete ci_all_required_passed safe_to_enable; do
        if ! echo "$json" | jq -e --arg k "$amk" '.auto_merge_readiness | has($k) and (.[$k] | type == "boolean")' >/dev/null 2>&1; then
          echo "FAIL [$target]: auto_merge_readiness.$amk missing or not boolean" >&2
          return 1
        fi
      done
      if ! echo "$json" | jq -e '.auto_merge_readiness | has("blockers") and (.blockers | type == "array")' >/dev/null 2>&1; then
        echo "FAIL [$target]: auto_merge_readiness.blockers missing or not an array" >&2
        return 1
      fi
      if ! echo "$json" | jq -e '.reviews | has("re_review_signal")' >/dev/null 2>&1; then
        echo "FAIL [$target]: reviews.re_review_signal missing" >&2
        return 1
      fi
      for sub in latest_cr_trigger_created_at latest_cr_review_submitted_at_after_trigger cr_response_pending_after_latest_trigger trigger_comment_log; do
        if ! echo "$json" | jq -e ".reviews.re_review_signal | has(\"$sub\")" >/dev/null 2>&1; then
          echo "FAIL [$target]: reviews.re_review_signal missing '$sub'" >&2
          return 1
        fi
      done
      if ! echo "$json" | jq -e '.reviews.re_review_signal.trigger_comment_log | type == "array"' >/dev/null 2>&1; then
        echo "FAIL [$target]: reviews.re_review_signal.trigger_comment_log must be an array" >&2
        return 1
      fi
      if ! echo "$json" | jq -e '.reviews.diagnostics | has("rereview_response_pending")' >/dev/null 2>&1; then
        echo "FAIL [$target]: reviews.diagnostics.rereview_response_pending missing" >&2
        return 1
      fi
      for dk in required_bot_findings_outstanding non_thread_bot_findings_outstanding; do
        if ! echo "$json" | jq -e --arg k "$dk" '.reviews.diagnostics | has($k) and (.[$k] | type == "boolean")' >/dev/null 2>&1; then
          echo "FAIL [$target]: reviews.diagnostics.$dk missing or not boolean" >&2
          return 1
        fi
      done
      for diagk in required_bot_rate_limited required_bot_timed_out; do
        if ! echo "$json" | jq -e --arg k "$diagk" '.reviews.diagnostics | has($k) and (.[$k] | type == "boolean")' >/dev/null 2>&1; then
          echo "FAIL [$target]: reviews.diagnostics.$diagk missing or not boolean" >&2
          return 1
        fi
      done
      if ! echo "$json" | jq -e '.reviews | has("review_threads_truncated") and (.review_threads_truncated | type == "boolean")' >/dev/null 2>&1; then
        echo "FAIL [$target]: reviews.review_threads_truncated missing or not boolean" >&2
        return 1
      fi
      ;;
    evidence-fsm)
      for key in workflow_position environment issues_summary pull_request routing; do
        if ! echo "$json" | jq -e "has(\"$key\")" >/dev/null 2>&1; then
          echo "FAIL [$target]: missing required key '$key'" >&2
          return 1
        fi
      done
      ;;
    evidence-issue)
      for key in issues dependency_graph; do
        if ! echo "$json" | jq -e "has(\"$key\")" >/dev/null 2>&1; then
          echo "FAIL [$target]: missing required key '$key'" >&2
          return 1
        fi
      done
      ;;
    evidence-review-threads)
      for key in total unresolved threads body_findings body_findings_count files_changed truncated; do
        if ! echo "$json" | jq -e "has(\"$key\")" >/dev/null 2>&1; then
          echo "FAIL [$target]: missing required key '$key'" >&2
          return 1
        fi
      done
      ;;
  esac

  echo "OK [$target]"
  return 0
}

if [ "${1:-}" != "" ]; then
  # Validate single target from stdin or golden file
  target="$1"
  golden="$GOLDEN_DIR/$target.json"
  if [ -f "$golden" ]; then
    case "$target" in
      evidence-workflow-position-*)
        validate_json "$golden" "evidence-workflow-position" || errors=$((errors + 1))
        ;;
      *)
        validate_json "$golden" "$target" || errors=$((errors + 1))
        ;;
    esac
  else
    echo "FAIL [$target]: no golden file at $golden" >&2
    errors=$((errors + 1))
  fi
else
  # Validate all golden files
  if [ ! -d "$GOLDEN_DIR" ]; then
    echo "FAIL: golden directory $GOLDEN_DIR not found" >&2
    exit 1
  fi

  for golden in "$GOLDEN_DIR"/*.json; do
    [ -f "$golden" ] || continue
    base=$(basename "$golden" .json)
    # Variants share the same emitted _meta.target as evidence-workflow-position
    case "$base" in
      evidence-workflow-position-*)
        validate_json "$golden" "evidence-workflow-position" || errors=$((errors + 1))
        ;;
      *)
        validate_json "$golden" "$base" || errors=$((errors + 1))
        ;;
    esac
  done
fi

if [ "$errors" -gt 0 ]; then
  echo "FAIL: $errors validation error(s)" >&2
  exit 1
fi

echo "OK: all evidence schemas valid"
