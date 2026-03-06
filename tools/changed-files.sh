#!/usr/bin/env bash
# tools/changed-files.sh -- List changed files matching given glob patterns
# Usage: tools/changed-files.sh "R/*.R" "tests/testthat/*.R"
#
# Compares against:
#   - PR context (GITHUB_BASE_REF): merge-base with base branch
#   - Local: merge-base with origin/main, or HEAD~1 as fallback
set -euo pipefail

if [[ -n "${GITHUB_BASE_REF:-}" ]]; then
  base="origin/${GITHUB_BASE_REF}"
elif git rev-parse --verify origin/main &>/dev/null; then
  base=$(git merge-base HEAD origin/main 2>/dev/null || echo "HEAD~1")
else
  base="HEAD~1"
fi

for pattern in "$@"; do
  git diff --name-only --diff-filter=ACMR "$base"...HEAD -- "$pattern" 2>/dev/null || true
done | sort -u
