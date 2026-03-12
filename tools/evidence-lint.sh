#!/usr/bin/env bash
# tools/evidence-lint.sh -- Structured lint results
# Requires container for R execution.
set -euo pipefail
# shellcheck disable=SC1091 source=evidence-lib.sh
. "$(dirname "$0")/evidence-lib.sh"

evidence_init "evidence-lint"

CONTAINER_NAME="${CONTAINER_NAME:-bridle-dev}"
RUNTIME="${RUNTIME:-$(command -v podman >/dev/null 2>&1 && echo podman || echo docker)}"
WORKDIR="/home/rstudio/bridle"

lint_json=""
if $RUNTIME inspect "$CONTAINER_NAME" --format '{{.State.Running}}' 2>/dev/null | grep -q true; then
  lint_json=$($RUNTIME exec -w "$WORKDIR" "$CONTAINER_NAME" \
    Rscript -e "
      pkgload::load_all('.', quiet = TRUE)
      lints <- lintr::lint_package()
      findings <- lapply(lints, function(l) {
        list(
          file = as.character(l\$filename),
          line = as.integer(l\$line_number),
          column = as.integer(l\$column_number),
          linter = as.character(l\$linter),
          message = as.character(l\$message),
          severity = as.character(l\$type)
        )
      })
      cat(jsonlite::toJSON(findings, auto_unbox = TRUE))
    " 2>/dev/null) || {
    evidence_error "Rscript" "lintr execution failed" false
    lint_json="[]"
  }
else
  evidence_error "container" "Container $CONTAINER_NAME is not running" true
  evidence_emit '{}'
  exit 0
fi

if ! echo "$lint_json" | jq . >/dev/null 2>&1; then
  evidence_error "lintr" "Failed to parse lint output as JSON" true
  evidence_emit '{}'
  exit 0
fi

finding_count=$(echo "$lint_json" | jq 'length')
file_count=$(echo "$lint_json" | jq '[.[].file] | unique | length')

body=$(jq -nc \
  --argjson fc "$file_count" \
  --argjson fnc "$finding_count" \
  --argjson findings "$lint_json" \
  '{
    "file_count": $fc,
    "finding_count": $fnc,
    "findings": $findings
  }')

evidence_emit "$body"
