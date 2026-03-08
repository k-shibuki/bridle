#!/usr/bin/env bash
# tools/pre-push.sh -- Local verification gate before push (HS#2)
# Blocks pushes when quality gates fail for R source or schema changes.
# Registered as a pre-push hook via pre-commit framework.
set -euo pipefail

# --- Emergency bypass ---
if [[ "${SKIP_PRE_PUSH:-0}" == "1" ]]; then
  echo "WARNING: pre-push verification bypassed (SKIP_PRE_PUSH=1)." >&2
  echo "CI is the last line of defense." >&2
  exit 0
fi

# --- Detect changed files ---
changed=$(git diff --name-only "@{push}.." 2>/dev/null \
  || git diff --name-only origin/main..HEAD 2>/dev/null \
  || true)

if [[ -z "$changed" ]]; then
  exit 0
fi

r_changed=$(echo "$changed" | grep -E '^(R/|tests/|DESCRIPTION|NAMESPACE)' || true)
schema_changed=$(echo "$changed" | grep -E '^(docs/schemas/|tools/validate)' || true)

# --- Nothing to verify ---
if [[ -z "$r_changed" && -z "$schema_changed" ]]; then
  exit 0
fi

# --- Container check ---
if [[ "${BRIDLE_IN_CONTAINER:-}" != "1" ]]; then
  RUNTIME=""
  if command -v podman &>/dev/null; then
    RUNTIME="podman"
  elif command -v docker &>/dev/null; then
    RUNTIME="docker"
  fi

  if [[ -z "$RUNTIME" ]]; then
    echo "BLOCKED (HS#2): No container runtime found (podman or docker required)." >&2
    exit 1
  fi

  if ! $RUNTIME inspect bridle-dev --format '{{.State.Running}}' 2>/dev/null | grep -q true; then
    echo "BLOCKED (HS#2): Container 'bridle-dev' is not running." >&2
    echo "Run 'make container-up' first, or set SKIP_PRE_PUSH=1 to bypass." >&2
    exit 1
  fi
fi

# --- Run verification gates ---
if [[ -n "$r_changed" ]]; then
  echo "pre-push: R source changes detected — running ci-fast + format-check..."
  make ci-fast || { echo "BLOCKED (HS#2): make ci-fast failed" >&2; exit 1; }
  make format-check || { echo "BLOCKED (HS#2): make format-check failed" >&2; exit 1; }
elif [[ -n "$schema_changed" ]]; then
  echo "pre-push: Schema changes detected — running validate-schemas..."
  make validate-schemas || { echo "BLOCKED (HS#2): make validate-schemas failed" >&2; exit 1; }
fi
