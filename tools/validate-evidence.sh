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
      for key in git issues pull_requests environment; do
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
      for key in number title ci merge reviews traceability; do
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
    validate_json "$golden" "$target" || errors=$((errors + 1))
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
    target=$(basename "$golden" .json)
    validate_json "$golden" "$target" || errors=$((errors + 1))
  done
fi

if [ "$errors" -gt 0 ]; then
  echo "FAIL: $errors validation error(s)" >&2
  exit 1
fi

echo "OK: all evidence schemas valid"
