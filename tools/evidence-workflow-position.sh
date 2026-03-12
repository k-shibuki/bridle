#!/usr/bin/env bash
# tools/evidence-workflow-position.sh -- Primary FSM input
# Aggregates git, GitHub, and environment state into a single JSON document.
# Network access: GitHub API (gh)
set -euo pipefail
# shellcheck disable=SC1091 source=evidence-lib.sh
. "$(dirname "$0")/evidence-lib.sh"

evidence_init "evidence-workflow-position"

# --- Git state ---
git_branch=$(git branch --show-current 2>/dev/null || echo "")
git_on_main=false
[ "$git_branch" = "main" ] && git_on_main=true

git_uncommitted=$(git status --short 2>/dev/null | wc -l | tr -d ' ')

git_stale_branches="[]"
stale=$(git branch --format='%(refname:short) %(upstream:track)' 2>/dev/null \
  | grep '\[gone\]' | awk '{print $1}' || true)
if [ -n "$stale" ]; then
  git_stale_branches=$(echo "$stale" | jq -Rsc 'split("\n") | map(select(length > 0))')
fi

git_ahead=0
ahead_behind=$(git rev-list --left-right --count "HEAD...@{upstream}" 2>/dev/null || echo "0 0")
git_ahead=$(echo "$ahead_behind" | awk '{print $1}')

git_stash=$(git stash list 2>/dev/null | wc -l | tr -d ' ')

git_json=$(jq -nc \
  --arg branch "$git_branch" \
  --argjson on_main "$git_on_main" \
  --argjson uncommitted "$git_uncommitted" \
  --argjson stale "$git_stale_branches" \
  --argjson ahead "$git_ahead" \
  --argjson stash "$git_stash" \
  '{
    "branch": $branch,
    "on_main": $on_main,
    "uncommitted_files": $uncommitted,
    "stale_branches": $stale,
    "commits_ahead_of_remote": $ahead,
    "stash_count": $stash
  }')

# --- Issues state ---
issues_json='{"open_count": 0, "open": []}'
if command -v gh >/dev/null 2>&1; then
  raw_issues=$(gh issue list --state open --json number,title,labels,body --limit 50 2>/dev/null || echo "[]")
  issues_open=$(echo "$raw_issues" | jq -c '[.[] | {
    number: .number,
    title: .title,
    labels: [.labels[].name],
    has_test_plan: ((.body // "") | test("## Test Plan"; "i")),
    blocked_by: ([(.body // "") | scan("#(\\d+)"; "g") | .[0] | tonumber] | unique)
  }]')
  issues_count=$(echo "$issues_open" | jq 'length')
  issues_json=$(jq -nc --argjson count "$issues_count" --argjson open "$issues_open" \
    '{"open_count": $count, "open": $open}')
fi

# --- Pull requests state ---
prs_json='{"open_count": 0, "open": [], "recently_merged": []}'
if command -v gh >/dev/null 2>&1; then
  raw_prs=$(gh pr list --state open \
    --json number,title,headRefName,statusCheckRollup,mergeable \
    --limit 10 2>/dev/null || echo "[]")

  prs_open=$(echo "$raw_prs" | jq -c '[.[] | {
    number: .number,
    title: .title,
    head_branch: .headRefName,
    ci_status: (
      if (.statusCheckRollup | length) == 0 then "no_checks"
      elif [.statusCheckRollup[] | select(.conclusion == "FAILURE")] | length > 0 then "failure"
      elif [.statusCheckRollup[] | select(.status != "COMPLETED")] | length > 0 then "pending"
      else "success"
      end
    ),
    mergeable: (.mergeable // "UNKNOWN"),
    review_threads_total: 0,
    review_threads_unresolved: 0
  }]')

  # Enrich with review thread counts via GraphQL
  owner=$(gh repo view --json owner --jq '.owner.login' 2>/dev/null || echo "")
  repo=$(gh repo view --json name --jq '.name' 2>/dev/null || echo "")
  if [ -n "$owner" ] && [ -n "$repo" ]; then
    for pr_num in $(echo "$prs_open" | jq -r '.[].number'); do
      # shellcheck disable=SC2016
      threads=$(gh api graphql -f query='
        query($owner: String!, $repo: String!, $pr: Int!) {
          repository(owner: $owner, name: $repo) {
            pullRequest(number: $pr) {
              reviewThreads(first: 100) {
                totalCount
                nodes { isResolved }
              }
            }
          }
        }
      ' -f owner="$owner" -f repo="$repo" -F pr="$pr_num" \
        --jq '{
          total: .data.repository.pullRequest.reviewThreads.totalCount,
          unresolved: [.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved | not)] | length
        }' 2>/dev/null || echo '{"total":0,"unresolved":0}')

      total=$(echo "$threads" | jq '.total')
      unresolved=$(echo "$threads" | jq '.unresolved')
      prs_open=$(echo "$prs_open" | jq -c \
        --argjson num "$pr_num" --argjson t "$total" --argjson u "$unresolved" \
        '[.[] | if .number == $num then .review_threads_total = $t | .review_threads_unresolved = $u else . end]')
    done
  fi

  prs_count=$(echo "$prs_open" | jq 'length')

  raw_merged=$(gh pr list --state merged --json number,title,mergedAt --limit 5 2>/dev/null || echo "[]")
  prs_merged=$(echo "$raw_merged" | jq -c '[.[] | {
    number: .number,
    title: .title,
    merged_at: .mergedAt
  }]')

  prs_json=$(jq -nc \
    --argjson count "$prs_count" \
    --argjson open "$prs_open" \
    --argjson merged "$prs_merged" \
    '{"open_count": $count, "open": $open, "recently_merged": $merged}')
fi

# --- Environment state ---
doctor_healthy=false
container_running=false

if command -v "${RUNTIME:-podman}" >/dev/null 2>&1; then
  cname="${CONTAINER_NAME:-bridle-dev}"
  runtime="${RUNTIME:-$(command -v podman >/dev/null 2>&1 && echo podman || echo docker)}"
  if $runtime inspect "$cname" --format '{{.State.Running}}' 2>/dev/null | grep -q true; then
    container_running=true
  fi
fi

if bash "$(dirname "$0")/doctor.sh" >/dev/null 2>&1; then
  doctor_healthy=true
fi

env_json=$(jq -nc \
  --argjson healthy "$doctor_healthy" \
  --argjson running "$container_running" \
  '{"doctor_healthy": $healthy, "container_running": $running}')

# --- Compose final output ---
body=$(jq -nc \
  --argjson git "$git_json" \
  --argjson issues "$issues_json" \
  --argjson prs "$prs_json" \
  --argjson env "$env_json" \
  '{
    "git": $git,
    "issues": $issues,
    "pull_requests": $prs,
    "environment": $env
  }')

evidence_emit "$body"
