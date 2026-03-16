#!/usr/bin/env bash
# tools/evidence-workflow-position.sh -- Primary FSM input
# Aggregates git, GitHub, and environment state into a single JSON document.
# Sections (git, issues, prs, env) run in parallel for performance.
# Network access: GitHub API (gh)
set -euo pipefail
# shellcheck disable=SC1091 source=evidence-lib.sh
. "$(dirname "$0")/evidence-lib.sh"

evidence_init "evidence-workflow-position"

_tmpdir=$(mktemp -d)
trap 'rm -rf "$_tmpdir"' EXIT

# --- Section: Git state (local only) ---
_collect_git() {
  local branch on_main uncommitted stale_branches ahead stash ahead_behind stale
  branch=$(git branch --show-current 2>/dev/null || echo "")
  on_main=false
  [ "$branch" = "main" ] && on_main=true

  uncommitted=$(git status --short 2>/dev/null | wc -l | tr -d ' ')

  stale_branches="[]"
  stale=$(git branch --format='%(refname:short) %(upstream:track)' 2>/dev/null \
    | grep '\[gone\]' | awk '{print $1}' || true)
  if [ -n "$stale" ]; then
    stale_branches=$(echo "$stale" | jq -Rsc 'split("\n") | map(select(length > 0))')
  fi

  ahead=0
  ahead_behind=$(git rev-list --left-right --count "HEAD...@{upstream}" 2>/dev/null || echo "0 0")
  ahead=$(echo "$ahead_behind" | awk '{print $1}')

  stash=$(git stash list 2>/dev/null | wc -l | tr -d ' ')

  jq -nc \
    --arg branch "$branch" \
    --argjson on_main "$on_main" \
    --argjson uncommitted "$uncommitted" \
    --argjson stale "$stale_branches" \
    --argjson ahead "$ahead" \
    --argjson stash "$stash" \
    '{
      "branch": $branch,
      "on_main": $on_main,
      "uncommitted_files": $uncommitted,
      "stale_branches": $stale,
      "commits_ahead_of_remote": $ahead,
      "stash_count": $stash
    }'
}

# --- Section: Issues state (1 API call) ---
_collect_issues() {
  if ! command -v gh >/dev/null 2>&1; then
    echo '{"open_count": 0, "open": []}'
    return
  fi
  local raw_issues issues_open issues_count
  raw_issues=$(gh issue list --state open --json number,title,labels,body --limit 50 2>/dev/null || echo "[]")
  issues_open=$(echo "$raw_issues" | jq -c '[.[] | {
    number: .number,
    title: .title,
    labels: [.labels[].name],
    has_test_plan: ((.body // "") | test("## Test Plan"; "i")),
    blocked_by: ([(.body // "") | scan("#(\\d+)"; "g") | .[0] | tonumber] | unique)
  }]')
  issues_count=$(echo "$issues_open" | jq 'length')
  jq -nc --argjson count "$issues_count" --argjson open "$issues_open" \
    '{"open_count": $count, "open": $open}'
}

# --- Section: Pull requests state (batched GraphQL for review threads) ---
_collect_prs() {
  if ! command -v gh >/dev/null 2>&1; then
    echo '{"open_count": 0, "open": [], "recently_merged": []}'
    return
  fi

  local raw_prs prs_open pr_numbers prs_count raw_merged prs_merged

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

  # Batched GraphQL: single query for all PRs using aliases
  pr_numbers=$(echo "$prs_open" | jq -r '.[].number')
  if [ -n "$pr_numbers" ]; then
    _resolve_repo
    if [ -n "$REPO_OWNER" ] && [ -n "$REPO_NAME" ]; then
      local query_body=""
      local num
      for num in $pr_numbers; do
        query_body="${query_body} pr${num}: pullRequest(number: ${num}) { reviewThreads(first: 100) { totalCount nodes { isResolved } } }"
      done

      local gql_query
      # shellcheck disable=SC2016
      gql_query='query($owner: String!, $repo: String!) { repository(owner: $owner, name: $repo) {'"${query_body}"' } }'

      local threads_result
      threads_result=$(gh api graphql \
        -f query="$gql_query" \
        -f owner="$REPO_OWNER" \
        -f repo="$REPO_NAME" \
        2>/dev/null || echo "")

      if [ -n "$threads_result" ]; then
        local total unresolved
        for num in $pr_numbers; do
          total=$(echo "$threads_result" | jq ".data.repository.pr${num}.reviewThreads.totalCount // 0")
          unresolved=$(echo "$threads_result" | jq "[.data.repository.pr${num}.reviewThreads.nodes[] | select(.isResolved | not)] | length" 2>/dev/null || echo "0")
          prs_open=$(echo "$prs_open" | jq -c \
            --argjson num "$num" --argjson t "$total" --argjson u "$unresolved" \
            '[.[] | if .number == $num then .review_threads_total = $t | .review_threads_unresolved = $u else . end]')
        done
      fi
    fi
  fi

  prs_count=$(echo "$prs_open" | jq 'length')

  raw_merged=$(gh pr list --state merged --json number,title,mergedAt --limit 5 2>/dev/null || echo "[]")
  prs_merged=$(echo "$raw_merged" | jq -c '[.[] | {
    number: .number,
    title: .title,
    merged_at: .mergedAt
  }]')

  jq -nc \
    --argjson count "$prs_count" \
    --argjson open "$prs_open" \
    --argjson merged "$prs_merged" \
    '{"open_count": $count, "open": $open, "recently_merged": $merged}'
}

# --- Section: Environment state (local only, no doctor.sh) ---
# Full diagnosis delegated to evidence-environment via the doctor action card.
_collect_env() {
  local container_running=false
  local cname="${CONTAINER_NAME:-bridle-dev}"
  local runtime="${RUNTIME:-$(command -v podman >/dev/null 2>&1 && echo podman || echo docker)}"

  if command -v "$runtime" >/dev/null 2>&1; then
    if $runtime inspect "$cname" --format '{{.State.Running}}' 2>/dev/null | grep -q true; then
      container_running=true
    fi
  fi

  jq -nc \
    --argjson healthy "$container_running" \
    --argjson running "$container_running" \
    '{"doctor_healthy": $healthy, "container_running": $running}'
}

# --- Section: Procedure context (local state file) ---
_collect_procedure_context() {
  local state_file=".cursor/state/workflow-phase.json"
  local phase="null" issue_number="null" ctx_branch="" updated_at="" stale="false"

  if [ ! -f "$state_file" ]; then
    jq -nc '{"workflow_phase": null, "stale": false}'
    return
  fi

  local raw
  if ! raw=$(jq -c '.' "$state_file" 2>/dev/null); then
    evidence_error "procedure_context" "Invalid JSON in $state_file" false
    jq -nc '{"workflow_phase": null, "stale": false}'
    return
  fi

  phase=$(echo "$raw" | jq -r '.workflow_phase // ""')
  issue_number=$(echo "$raw" | jq '.issue_number // null')
  ctx_branch=$(echo "$raw" | jq -r '.branch // ""')
  updated_at=$(echo "$raw" | jq -r '.updated_at // ""')

  # Stale detection: branch mismatch or > 24h old
  local current_branch
  current_branch=$(git branch --show-current 2>/dev/null || echo "")
  if [ -n "$ctx_branch" ] && [ "$ctx_branch" != "$current_branch" ]; then
    stale="true"
  fi
  if [ -n "$updated_at" ]; then
    local now_epoch updated_epoch age_hours
    now_epoch=$(date +%s)
    updated_epoch=$(date -d "$updated_at" +%s 2>/dev/null || echo "$now_epoch")
    age_hours=$(( (now_epoch - updated_epoch) / 3600 ))
    if [ "$age_hours" -ge 24 ]; then
      stale="true"
    fi
  fi

  jq -nc \
    --arg phase "$phase" \
    --argjson issue "$issue_number" \
    --arg branch "$ctx_branch" \
    --arg updated "$updated_at" \
    --argjson stale "$stale" \
    '{
      "workflow_phase": (if $phase == "" then null else $phase end),
      "issue_number": $issue,
      "branch": $branch,
      "updated_at": (if $updated == "" then null else $updated end),
      "stale": $stale
    }'
}

# --- Run all sections in parallel ---
_collect_git > "$_tmpdir/git.json" &
pid_git=$!
_collect_issues > "$_tmpdir/issues.json" &
pid_issues=$!
_collect_prs > "$_tmpdir/prs.json" &
pid_prs=$!
_collect_env > "$_tmpdir/env.json" &
pid_env=$!
_collect_procedure_context > "$_tmpdir/ctx.json" &
pid_ctx=$!

wait "$pid_git" || evidence_error "git" "Git collection failed" false
wait "$pid_issues" || evidence_error "issues" "Issues collection failed" false
wait "$pid_prs" || evidence_error "prs" "PRs collection failed" false
wait "$pid_env" || evidence_error "env" "Environment collection failed" false
wait "$pid_ctx" || evidence_error "procedure_context" "Procedure context collection failed" false

# Defaults for sections that produced no output
[ -s "$_tmpdir/git.json" ] || echo '{"branch":"","on_main":false,"uncommitted_files":0,"stale_branches":[],"commits_ahead_of_remote":0,"stash_count":0}' > "$_tmpdir/git.json"
[ -s "$_tmpdir/issues.json" ] || echo '{"open_count":0,"open":[]}' > "$_tmpdir/issues.json"
[ -s "$_tmpdir/prs.json" ] || echo '{"open_count":0,"open":[],"recently_merged":[]}' > "$_tmpdir/prs.json"
[ -s "$_tmpdir/env.json" ] || echo '{"doctor_healthy":false,"container_running":false}' > "$_tmpdir/env.json"
[ -s "$_tmpdir/ctx.json" ] || echo '{"workflow_phase":null,"stale":false}' > "$_tmpdir/ctx.json"

# --- Compose final output ---
body=$(jq -nc \
  --slurpfile git "$_tmpdir/git.json" \
  --slurpfile issues "$_tmpdir/issues.json" \
  --slurpfile prs "$_tmpdir/prs.json" \
  --slurpfile env "$_tmpdir/env.json" \
  --slurpfile ctx "$_tmpdir/ctx.json" \
  '{
    "git": $git[0],
    "issues": $issues[0],
    "pull_requests": $prs[0],
    "environment": $env[0],
    "procedure_context": $ctx[0]
  }')

evidence_emit "$body"
