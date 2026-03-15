#!/usr/bin/env bash
# tools/pre-push.sh -- Local verification gate before push (HS-LOCAL-VERIFY)
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
renv_changed=$(echo "$changed" | grep -E '^(DESCRIPTION|renv\.lock|renv/)' || true)
# knowledge-validate checks atom/index consistency; review-sync-verify validates
# AGENTS.md ↔ pr-review.md category parity. Both run when any KB file changes.
kb_changed=$(echo "$changed" | grep -E '^(\.cursor/(knowledge/|rules/knowledge-index\.mdc|commands/pr-review\.md)|AGENTS\.md)' || true)
md_changed=$(echo "$changed" | grep -E '\.md$' || true)

# --- Nothing to verify ---
if [[ -z "$r_changed" && -z "$schema_changed" && -z "$renv_changed" && -z "$kb_changed" && -z "$md_changed" ]]; then
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
    echo "BLOCKED (HS-LOCAL-VERIFY): No container runtime found (podman or docker required)." >&2
    exit 1
  fi

  if ! $RUNTIME inspect bridle-dev --format '{{.State.Running}}' 2>/dev/null | grep -q true; then
    echo "BLOCKED (HS-LOCAL-VERIFY): Container 'bridle-dev' is not running." >&2
    echo "Run 'make container-start' first, or set SKIP_PRE_PUSH=1 to bypass." >&2
    exit 1
  fi
fi

# --- Run verification gates (independent blocks — all matching types trigger) ---
if [[ -n "$r_changed" ]]; then
  echo "pre-push: R source changes detected — running format-verify + lint-changed + test-changed..."
  make format-verify || { echo "BLOCKED (HS-LOCAL-VERIFY): make format-verify failed" >&2; exit 1; }
  make lint-changed || { echo "BLOCKED (HS-LOCAL-VERIFY): make lint-changed failed" >&2; exit 1; }
  make test-changed || { echo "BLOCKED (HS-LOCAL-VERIFY): make test-changed failed" >&2; exit 1; }
fi

if [[ -n "$schema_changed" ]]; then
  echo "pre-push: Schema changes detected — running schema-validate..."
  make schema-validate || { echo "BLOCKED (HS-LOCAL-VERIFY): make schema-validate failed" >&2; exit 1; }
fi

if [[ -n "$renv_changed" ]]; then
  echo "pre-push: DESCRIPTION/renv changes detected — running package-sync-verify..."
  make package-sync-verify || { echo "BLOCKED (HS-LOCAL-VERIFY): make package-sync-verify failed" >&2; exit 1; }
fi

if [[ -n "$kb_changed" ]]; then
  echo "pre-push: Knowledge base changes detected — running knowledge-validate + review-sync-verify..."
  make knowledge-validate || { echo "BLOCKED (HS-LOCAL-VERIFY): make knowledge-validate failed. Run 'make knowledge-manifest' to update the index, then stage and commit." >&2; exit 1; }
  make review-sync-verify || { echo "BLOCKED (HS-LOCAL-VERIFY): make review-sync-verify failed. AGENTS.md and pr-review.md categories are out of sync." >&2; exit 1; }
fi

if [[ -n "$md_changed" ]]; then
  echo "pre-push: Markdown changes detected — running markdown-lint-changed..."
  make markdown-lint-changed || { echo "BLOCKED (HS-LOCAL-VERIFY): make markdown-lint-changed failed" >&2; exit 1; }
fi
