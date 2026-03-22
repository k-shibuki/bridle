#!/usr/bin/env bash
# Offline regression: merge-gate CI rollup filter (tools/jq/evidence-ci-gate-defs.jq).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JQ_DIR="$ROOT/tools/jq"
CFG="$ROOT/docs/agent-control/review-bots.json"
run_gate() {
  local rollup="$1"
  jq -n \
    --argjson rollup "$rollup" \
    --argjson cfg "$(jq -c '.' "$CFG")" \
    -f <(cat "$JQ_DIR/evidence-ci-gate-defs.jq" "$JQ_DIR/evidence-ci-gate-single.jq")
}

# Bot-named check still PENDING must not block merge-gate ci_status when real CI is green
out=$(run_gate '[{"name":"ci-pass","status":"COMPLETED","conclusion":"SUCCESS"},{"name":"CodeRabbit","status":"PENDING","conclusion":null}]')
if [ "$(echo "$out" | jq -r '.ci_status')" != "success" ]; then
  echo "FAIL: expected ci_status success when CodeRabbit pending but gate green, got: $out" >&2
  exit 1
fi

# Only bot check → no_checks after filter (matches evidence-pull-request semantics)
out=$(run_gate '[{"name":"CodeRabbit","status":"COMPLETED","conclusion":"SUCCESS"}]')
if [ "$(echo "$out" | jq -r '.ci_status')" != "no_checks" ]; then
  echo "FAIL: expected no_checks when only bot checks present, got: $out" >&2
  exit 1
fi

echo "OK evidence-ci-gate"
