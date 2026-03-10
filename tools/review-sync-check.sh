#!/bin/sh
# review-sync-check.sh — Detect drift between AGENTS.md and pr-review.md review categories.
#
# Both files define review criteria for different tools (Codex and Cursor).
# They are intentionally separate (not SSOT) but should cover the same core
# categories. This script warns when a core category keyword appears in only
# one of the two files.
#
# Usage: sh tools/review-sync-check.sh

set -e

AGENTS_FILE="${AGENTS_FILE:-AGENTS.md}"
PR_REVIEW_FILE="${PR_REVIEW_FILE:-.cursor/commands/pr-review.md}"

if [ ! -f "$AGENTS_FILE" ]; then
  echo "SKIP: $AGENTS_FILE not found (Codex review not configured)" >&2
  exit 0
fi

if [ ! -f "$PR_REVIEW_FILE" ]; then
  echo "ERROR: $PR_REVIEW_FILE not found" >&2
  exit 1
fi

# Core review categories that should be covered by both files.
# Format: display_name|grep_pattern (case-insensitive extended grep)
CATEGORIES="
Type safety|type.safety|S7
Test quality|test.quality
Traceability|traceability|Closes #|Refs: #
ADR compliance|ADR|spec.alignment
Security|security|authentication|authorization
Code quality|code.quality|readability|naming|duplication
"

rm -f /tmp/review_sync_warn_flag

echo "Checking review category coverage between:"
echo "  AGENTS:    $AGENTS_FILE"
echo "  pr-review: $PR_REVIEW_FILE"
echo ""

echo "$CATEGORIES" | while IFS='|' read -r name patterns; do
  [ -z "$name" ] && continue
  name=$(echo "$name" | sed 's/^[[:space:]]*//')

  in_agents=0
  in_review=0

  # $patterns is already a pipe-delimited ERE alternation (e.g. "traceability|Closes #|Refs: #").
  # Quoting prevents word-splitting on spaces within patterns.
  patterns=$(echo "$patterns" | sed 's/^[[:space:]]*//')
  if grep -qiE "$patterns" "$AGENTS_FILE" 2>/dev/null; then
    in_agents=1
  fi
  if grep -qiE "$patterns" "$PR_REVIEW_FILE" 2>/dev/null; then
    in_review=1
  fi

  if [ "$in_agents" -eq 1 ] && [ "$in_review" -eq 0 ]; then
    echo "WARN: '$name' found in $AGENTS_FILE but not in $PR_REVIEW_FILE" >&2
    touch /tmp/review_sync_warn_flag
  elif [ "$in_agents" -eq 0 ] && [ "$in_review" -eq 1 ]; then
    echo "WARN: '$name' found in $PR_REVIEW_FILE but not in $AGENTS_FILE" >&2
    touch /tmp/review_sync_warn_flag
  fi
done

if [ -f /tmp/review_sync_warn_flag ]; then
  rm -f /tmp/review_sync_warn_flag
  echo ""
  echo "WARN: Review category drift detected. Update both files to stay in sync."
  echo "  AGENTS.md: Codex Cloud review guidelines"
  echo "  pr-review.md: Cursor manual review categories (Step 6)"
  exit 1
fi

echo "OK: review categories are in sync"
