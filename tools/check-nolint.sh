#!/usr/bin/env bash
# tools/check-nolint.sh -- Validate nolint annotation format (HS-NOLINT)
# Rejects bare, blanket, and reason-less nolint annotations.
# Registered as a pre-commit hook via pre-commit framework.
# Accepts: # nolint: <linter_name>. <reason>
set -euo pipefail

errors=0

for file in "$@"; do
  [[ -f "$file" ]] || continue

  # Bare # nolint (no linter name, no colon)
  if grep -nP '# nolint\s*$' "$file"; then
    echo "BLOCKED (HS-NOLINT): $file — bare '# nolint' without linter name and reason" >&2
    errors=1
  fi

  # Blanket # nolint start/end
  if grep -nP '# nolint\s+(start|end)' "$file"; then
    echo "BLOCKED (HS-NOLINT): $file — blanket '# nolint start/end' is prohibited" >&2
    errors=1
  fi

  # # nolint: with no linter (just colon, nothing after)
  if grep -nP '# nolint:\s*$' "$file"; then
    echo "BLOCKED (HS-NOLINT): $file — '# nolint:' requires linter name and reason" >&2
    errors=1
  fi

  # # nolint: <linter> without ". <reason>"
  if grep -nP '# nolint:\s+\w+\s*$' "$file"; then
    echo "BLOCKED (HS-NOLINT): $file — '# nolint: <linter>' requires a reason: '# nolint: <linter>. <reason>'" >&2
    errors=1
  fi

  # # nolint: <linter>. (period but empty/whitespace-only reason)
  if grep -nP '# nolint:\s+\w+\.\s*$' "$file"; then
    echo "BLOCKED (HS-NOLINT): $file — '# nolint: <linter>.' requires a non-empty reason after the period" >&2
    errors=1
  fi
done

exit $errors
