#!/usr/bin/env bash
# tools/label-agent-control-backfill.sh -- Create label agent-control and add to known control-system Issues
# Run from repo root. Requires gh CLI. Idempotent.
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
# List of Issue numbers that are agent-control scope (docs/agent-control, .cursor, tools/evidence*, pr-policy, etc.)
# Plan: #252, #253-257, #264, #269, #271-275; extend as needed.
BACKFILL_ISSUES=(252 253 254 255 256 257 264 269 271 272 273 274 275)

if ! command -v gh >/dev/null 2>&1; then
  echo "Error: gh CLI not found." >&2
  exit 1
fi

# Create label if it does not exist
if ! gh label view agent-control &>/dev/null; then
  gh label create agent-control \
    --color "0E8A16" \
    --description "Agent control system: docs/agent-control, .cursor, tools/evidence*, pr-policy"
fi

for n in "${BACKFILL_ISSUES[@]}"; do
  if gh issue view "$n" --json number,state &>/dev/null; then
    gh issue edit "$n" --add-label "agent-control" 2>/dev/null || true
  fi
done

echo "Label agent-control ensured; backfill applied to listed issues."
