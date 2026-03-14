#!/usr/bin/env bash
# tools/evidence-lib.sh -- Shared library for evidence targets
# Source this file from evidence scripts: . "$(dirname "$0")/evidence-lib.sh"
#
# Provides:
#   evidence_init TARGET_NAME   Initialize meta envelope, start timer
#   evidence_error SOURCE MSG [FATAL]   Record an error
#   evidence_emit JSON_BODY     Wrap body in meta envelope and print to stdout
#   _resolve_repo               Set REPO_OWNER and REPO_NAME from git remote (no API call)

set -euo pipefail

_EVIDENCE_TARGET=""
_EVIDENCE_START_MS=""
_EVIDENCE_ERRORS="[]"
_EVIDENCE_VERSION="1.0.0"

evidence_init() {
  _EVIDENCE_TARGET="$1"
  if command -v date >/dev/null 2>&1 && date +%s%N >/dev/null 2>&1; then
    _EVIDENCE_START_MS=$(( $(date +%s%N) / 1000000 ))
  else
    _EVIDENCE_START_MS=$(date +%s)000
  fi
  _EVIDENCE_ERRORS="[]"
}

evidence_error() {
  local source="$1" message="$2" fatal="${3:-false}"
  message=$(printf '%s' "$message" | tr '\n' ' ')
  _EVIDENCE_ERRORS=$(echo "$_EVIDENCE_ERRORS" | jq -c \
    --arg src "$source" --arg msg "$message" --argjson fatal "$fatal" \
    '. + [{"source": $src, "message": $msg, "fatal": $fatal}]')
}

evidence_emit() {
  local body="$1"
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local end_ms
  if date +%s%N >/dev/null 2>&1; then
    end_ms=$(( $(date +%s%N) / 1000000 ))
  else
    end_ms=$(date +%s)000
  fi
  local duration_ms=$(( end_ms - _EVIDENCE_START_MS ))

  local meta
  meta=$(jq -nc \
    --arg target "$_EVIDENCE_TARGET" \
    --arg ts "$now" \
    --arg ver "$_EVIDENCE_VERSION" \
    --argjson dur "$duration_ms" \
    '{"target": $target, "timestamp": $ts, "version": $ver, "duration_ms": $dur}')

  local has_fatal
  has_fatal=$(echo "$_EVIDENCE_ERRORS" | jq '[.[] | select(.fatal == true)] | length')

  if [ "$has_fatal" -gt 0 ]; then
    jq -nc --argjson meta "$meta" --argjson errors "$_EVIDENCE_ERRORS" \
      '{"_meta": $meta, "_errors": $errors}'
  elif [ "$(echo "$_EVIDENCE_ERRORS" | jq 'length')" -gt 0 ]; then
    echo "$body" | jq -c --argjson meta "$meta" --argjson errors "$_EVIDENCE_ERRORS" \
      '. + {"_meta": $meta, "_errors": $errors}'
  else
    echo "$body" | jq -c --argjson meta "$meta" \
      '. + {"_meta": $meta}'
  fi
}

# Sets REPO_OWNER and REPO_NAME from git remote origin (used by callers).
# shellcheck disable=SC2034
_resolve_repo() {
  local url
  url=$(git remote get-url origin 2>/dev/null || echo "")
  if [ -z "$url" ]; then
    REPO_OWNER=""
    REPO_NAME=""
    return 1
  fi
  # SSH:   git@github.com:owner/repo.git
  # HTTPS: https://github.com/owner/repo.git
  REPO_OWNER=$(echo "$url" | sed -E 's|.*[:/]([^/]+)/[^/]+\.git$|\1|; s|.*[:/]([^/]+)/[^/]+$|\1|')
  REPO_NAME=$(echo "$url" | sed -E 's|.*/([^/]+)\.git$|\1|; s|.*/([^/]+)$|\1|')
}

_require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: required command '$1' not found" >&2
    exit 1
  fi
}

_require_cmd jq
