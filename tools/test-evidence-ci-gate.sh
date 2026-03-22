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

# Bot name must match commit_status_name by equality (case-insensitive), not substring — do not drop unrelated checks
out=$(run_gate '[{"name":"ci-pass","status":"COMPLETED","conclusion":"SUCCESS"},{"name":"CodeRabbit fixtures","status":"COMPLETED","conclusion":"SUCCESS"}]')
if [ "$(echo "$out" | jq -r '.ci_status')" != "success" ]; then
  echo "FAIL: expected ci_status success when bot row is superset string of CodeRabbit, got: $out" >&2
  exit 1
fi

# Duplicate check name: stale FAILURE + latest SUCCESS → merge gate green
out=$(run_gate '[
  {"name":"check-policy","status":"COMPLETED","conclusion":"FAILURE","completedAt":"2026-03-22T02:08:28Z"},
  {"name":"check-policy","status":"COMPLETED","conclusion":"SUCCESS","completedAt":"2026-03-22T02:09:00Z"},
  {"name":"ci-pass","status":"COMPLETED","conclusion":"SUCCESS","completedAt":"2026-03-22T02:10:00Z"}
]')
if [ "$(echo "$out" | jq -r '.ci_status')" != "success" ]; then
  echo "FAIL: expected ci_status success when duplicate check name has latest SUCCESS, got: $out" >&2
  exit 1
fi

# Unknown completed conclusion fails closed (merge gate)
out=$(run_gate '[{"name":"ci-pass","status":"COMPLETED","conclusion":"NEUTRAL"}]')
if [ "$(echo "$out" | jq -r '.ci_status')" != "failure" ]; then
  echo "FAIL: expected ci_status failure for unknown conclusion, got: $out" >&2
  exit 1
fi
chk=$(echo "$out" | jq -r '.ci_checks[0].status')
if [ "$chk" != "fail" ]; then
  echo "FAIL: expected ci_checks[0].status fail for unknown conclusion, got: $chk" >&2
  exit 1
fi

echo "OK evidence-ci-gate"
