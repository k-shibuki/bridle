#!/usr/bin/env bash
# tools/evidence-branch-protection.sh -- Branch protection rules for default branch (observation only)
# Usage: BRANCH=main make evidence-branch-protection  (BRANCH optional, default main)
set -euo pipefail
# shellcheck disable=SC1091 source=evidence-lib.sh
. "$(dirname "$0")/evidence-lib.sh"

evidence_init "evidence-branch-protection"
_require_cmd gh

BRANCH="${BRANCH:-main}"

if ! _resolve_repo; then
  evidence_error "git" "could not resolve origin remote" true
  evidence_emit "$(jq -nc --arg br "$BRANCH" '{repo_owner: null, repo_name: null, branch: $br, protection_present: false, required_status_contexts: []}')"
  exit 1
fi

tmp_err=$(mktemp)
trap 'rm -f "$tmp_err"' EXIT

prot_json=""
if prot_json=$(gh api "repos/${REPO_OWNER}/${REPO_NAME}/branches/${BRANCH}/protection" 2>"$tmp_err"); then
  contexts=$(echo "$prot_json" | jq -c '.required_status_checks.contexts // []')
  strict=$(echo "$prot_json" | jq -c '.required_status_checks.strict // false')
  body=$(jq -nc \
    --arg owner "$REPO_OWNER" \
    --arg name "$REPO_NAME" \
    --arg br "$BRANCH" \
    --argjson ctx "$contexts" \
    --argjson st "$strict" \
    '{
      repo_owner: $owner,
      repo_name: $name,
      branch: $br,
      protection_present: true,
      required_status_checks_strict: $st,
      required_status_contexts: $ctx
    }')
else
  err=$(cat "$tmp_err" || true)
  if echo "$err" | grep -qiE '404|not found'; then
    body=$(jq -nc \
      --arg owner "$REPO_OWNER" \
      --arg name "$REPO_NAME" \
      --arg br "$BRANCH" \
      '{
        repo_owner: $owner,
        repo_name: $name,
        branch: $br,
        protection_present: false,
        required_status_checks_strict: null,
        required_status_contexts: []
      }')
  else
    evidence_error "gh api branch protection" "$err" true
    body=$(jq -nc \
      --arg owner "$REPO_OWNER" \
      --arg name "$REPO_NAME" \
      --arg br "$BRANCH" \
      '{repo_owner: $owner, repo_name: $name, branch: $br, protection_present: false, required_status_contexts: []}')
    evidence_emit "$body"
    exit 1
  fi
fi

evidence_emit "$body"
