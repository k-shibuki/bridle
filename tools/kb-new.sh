#!/bin/sh
# kb-new.sh — Scaffold a new atomic knowledge file.
# Usage: sh tools/kb-new.sh NAME=<category--topic>

set -e

KB_DIR=".cursor/knowledge"

# Parse NAME argument
NAME=""
for arg in "$@"; do
  case "$arg" in
    NAME=*) NAME="${arg#NAME=}" ;;
  esac
done

if [ -z "$NAME" ]; then
  echo "Usage: make knowledge-new NAME=<category--topic>" >&2
  echo "Example: make knowledge-new NAME=test--new-pattern" >&2
  exit 1
fi

# Validate naming convention: lowercase, -- separator, - for words
if ! echo "$NAME" | grep -qE '^[a-z]+--[a-z]([a-z0-9-]*[a-z0-9])?$'; then
  echo "ERROR: '$NAME' violates naming convention" >&2
  echo "  Required: {category}--{topic} (lowercase, -- separates category from topic, - separates words)" >&2
  echo "  Valid categories: test, r, lint, debug, ci, git, agent" >&2
  exit 1
fi

TARGET="$KB_DIR/$NAME.md"

if [ -f "$TARGET" ]; then
  echo "ERROR: $TARGET already exists" >&2
  exit 1
fi

cat > "$TARGET" << 'TEMPLATE'
---
trigger: TODO — add comma-separated trigger keywords
---
# TODO — Title

TODO — describe the single decision point this atom addresses.
TEMPLATE

echo "OK: created $TARGET"
echo "Next steps:"
echo "  1. Edit the file: fill trigger keywords, title, and content"
echo "  2. Run: make knowledge-manifest  (regenerate index)"
echo "  3. Run: make knowledge-validate  (verify consistency)"
