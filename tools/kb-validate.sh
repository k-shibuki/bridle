#!/bin/sh
# kb-validate.sh — Validate knowledge base consistency.
# Usage: sh tools/kb-validate.sh

set -e

KB_DIR=".cursor/knowledge"
INDEX_FILE=".cursor/rules/knowledge-index.mdc"
errors=0

if [ ! -d "$KB_DIR" ]; then
  echo "ERROR: $KB_DIR not found" >&2
  exit 1
fi

# 1. Check each atom file for valid structure
for f in "$KB_DIR"/*.md; do
  [ -f "$f" ] || continue

  basename=$(basename "$f")

  # Skip files not matching atom naming convention
  case "$basename" in
    [a-z]*--*.md) ;;
    *) continue ;;
  esac

  # Check naming convention: lowercase, -- separator, - for words
  if echo "$basename" | grep -qE '[A-Z]'; then
    echo "ERROR: $basename violates naming convention (uppercase found)" >&2
    errors=$((errors + 1))
  fi

  # Check YAML frontmatter exists
  first_line=$(head -n 1 "$f")
  if [ "$first_line" != "---" ]; then
    echo "ERROR: $basename missing YAML frontmatter (no opening ---)" >&2
    errors=$((errors + 1))
    continue
  fi

  # Check trigger: field exists
  has_trigger=0
  in_frontmatter=0
  while IFS= read -r line; do
    if [ "$in_frontmatter" -eq 0 ]; then
      if [ "$line" = "---" ]; then
        in_frontmatter=1
        continue
      fi
    fi
    if [ "$in_frontmatter" -eq 1 ] && [ "$line" = "---" ]; then
      break
    fi
    case "$line" in
      trigger:*) has_trigger=1 ;;
    esac
  done < "$f"

  if [ "$has_trigger" -eq 0 ]; then
    echo "ERROR: $basename missing trigger: field in frontmatter" >&2
    errors=$((errors + 1))
  fi
done

# 2. Check index file exists
if [ ! -f "$INDEX_FILE" ]; then
  echo "ERROR: $INDEX_FILE not found (run make kb-manifest)" >&2
  errors=$((errors + 1))
else
  # 3. Check for orphans in index (files listed but not existing)
  grep -oP "\`[a-z].*?--.*?\.md\`" "$INDEX_FILE" 2>/dev/null | tr -d '`' | while read -r indexed_file; do
    if [ ! -f "$KB_DIR/$indexed_file" ]; then
      echo "ERROR: $indexed_file listed in index but not found in $KB_DIR" >&2
      # Can't increment errors in subshell; use a flag file
      touch /tmp/kb_validate_error_flag
    fi
  done

  if [ -f /tmp/kb_validate_error_flag ]; then
    rm -f /tmp/kb_validate_error_flag
    errors=$((errors + 1))
  fi

  # 4. Check for atoms not in index
  for f in "$KB_DIR"/*.md; do
    [ -f "$f" ] || continue
    basename=$(basename "$f")
    case "$basename" in
      [a-z]*--*.md) ;;
      *) continue ;;
    esac
    if ! grep -q "$basename" "$INDEX_FILE" 2>/dev/null; then
      echo "ERROR: $basename exists but is not in index (run make kb-manifest)" >&2
      errors=$((errors + 1))
    fi
  done
fi

if [ "$errors" -gt 0 ]; then
  echo "FAILED: $errors error(s) found" >&2
  exit 1
fi

echo "OK: knowledge base is consistent"
