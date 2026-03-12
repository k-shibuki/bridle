#!/usr/bin/env bash
# tools/evidence-environment.sh -- Detailed environment health check
# Wraps tools/doctor.sh --json output in evidence envelope.
set -euo pipefail
# shellcheck disable=SC1091 source=evidence-lib.sh
. "$(dirname "$0")/evidence-lib.sh"

evidence_init "evidence-environment"

doctor_output=""
if doctor_output=$(bash "$(dirname "$0")/doctor.sh" --json 2>/dev/null); then
  :
else
  evidence_error "doctor.sh" "doctor check failed with exit code $?" false
  doctor_output='{"errors":0,"warnings":0,"runtime":"unknown","checks":[]}'
fi

errors=$(echo "$doctor_output" | jq '.errors // 0')
warnings=$(echo "$doctor_output" | jq '.warnings // 0')
runtime=$(echo "$doctor_output" | jq -r '.runtime // "unknown"')
checks=$(echo "$doctor_output" | jq -c '.checks // []')

body=$(jq -nc \
  --argjson errors "$errors" \
  --argjson warnings "$warnings" \
  --arg runtime "$runtime" \
  --argjson checks "$checks" \
  '{
    "errors": $errors,
    "warnings": $warnings,
    "runtime": $runtime,
    "checks": $checks
  }')

evidence_emit "$body"
