#!/usr/bin/env bash
# tools/parse-sub-issues.sh -- Extract child Issue numbers from ## Sub-issues section (stdin = Issue body)
# Output: JSON array of integers, e.g. [253, 254]. SSOT: docs/agent-control/evidence-schema.md
set -euo pipefail

body=$(cat)
# Extract section: from "## Sub-issues" or "### Sub-issues" until next "## " or end
section=$(echo "$body" | awk '
  /^#{2,3}[[:space:]]+Sub-issues[[:space:]]*$/ { in_section=1; next }
  in_section && /^##[[:space:]]/ { in_section=0 }
  in_section { print }
')
# Match list lines: - [ ] #N, - [x] #N, - #N, * [ ] #N. Plan §7. Portable: grep + sed.
nums=$(echo "$section" | grep -E '^[[:space:]]*[-*][[:space:]]+(\[[ xX]\][[:space:]]*)?#[0-9]+' | sed -n 's/.*#\([0-9][0-9]*\).*/\1/p' | grep -E '^[0-9]+$' || true)
# Unique, JSON array
if [ -z "$nums" ]; then
  echo "[]"
else
  echo "$nums" | sort -n | uniq | jq -R -s -c 'split("\n") | map(select(length > 0)) | map(tonumber) | unique'
fi
