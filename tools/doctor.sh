#!/usr/bin/env bash
# tools/doctor.sh -- Development environment health check
# Checks host-side prerequisites and (if container is running) R environment.
# Usage: bash tools/doctor.sh [--json]
set -euo pipefail

# --- Configuration ---
CONTAINER_NAME="bridle-dev"
MIN_R_VERSION="4.1.0"
REQUIRED_R_PKGS=(devtools testthat lintr styler S7 cli rlang yaml roxygen2)
OPTIONAL_R_PKGS=(covr ellmer jsonlite ragnar vitals mcptools reprex pkgdown withr)

# --- Output mode ---
JSON_MODE=false
if [[ "${1:-}" == "--json" ]]; then
  JSON_MODE=true
fi

# --- Auto-detect container runtime (podman preferred, docker fallback) ---
RUNTIME=""
if command -v podman &>/dev/null; then
  RUNTIME="podman"
elif command -v docker &>/dev/null; then
  RUNTIME="docker"
fi

# --- State ---
errors=0
warnings=0
declare -a results=()

# --- Helpers ---
record() {
  local name="$1" status="$2" detail="${3:-}"
  if $JSON_MODE; then
    results+=("{\"name\":\"$name\",\"status\":\"$status\",\"detail\":\"$detail\"}")
  else
    case "$status" in
      ok)   printf '\033[0;32m✓\033[0m %s\n' "$name" ;;
      fail) printf '\033[0;31m✗\033[0m %s (required) %s\n' "$name" "$detail" ;;
      warn) printf '\033[1;33m!\033[0m %s (optional) %s\n' "$name" "$detail" ;;
    esac
  fi
}

check_r_pkg() {
  local pkg="$1" required="${2:-true}"
  local out
  if out=$($RUNTIME exec -w /home/rstudio/bridle "$CONTAINER_NAME" \
      Rscript -e "cat(requireNamespace('$pkg', quietly = TRUE))" 2>/dev/null \
      | tail -1) \
      && [[ "$out" == "TRUE" ]]; then
    record "R pkg: $pkg" "ok"
  elif [[ "$required" == "true" ]]; then
    record "R pkg: $pkg" "fail" "not installed"
    errors=$((errors + 1))
  else
    record "R pkg: $pkg" "warn" "not installed"
    warnings=$((warnings + 1))
  fi
}

# --- Host checks ---
$JSON_MODE || echo "=== Host environment ==="
$JSON_MODE || echo ""

# Container runtime (podman or docker -- either is fine)
if [[ -n "$RUNTIME" ]]; then
  record "Container runtime: $RUNTIME" "ok"
else
  record "Container runtime (podman or docker)" "fail" "neither found"
  errors=$((errors + 1))
fi

if command -v git &>/dev/null; then
  record "git" "ok"
else
  record "git" "fail" "not found"
  errors=$((errors + 1))
fi

# Compose tool: podman-compose (standalone) or docker compose (V2 subcommand)
if command -v podman-compose &>/dev/null; then
  record "podman-compose" "ok"
elif docker compose version &>/dev/null 2>&1; then
  record "docker compose" "ok"
else
  record "compose" "warn" "not available (direct build/run used as fallback; renv cache volume not mounted)"
  warnings=$((warnings + 1))
fi

# Container running?
container_running=false
if [[ -n "$RUNTIME" ]]; then
  if $RUNTIME inspect "$CONTAINER_NAME" --format '{{.State.Running}}' 2>/dev/null | grep -q true; then
    record "Container '$CONTAINER_NAME'" "ok"
    container_running=true
  else
    record "Container '$CONTAINER_NAME'" "warn" "not running (run 'make container-up')"
    warnings=$((warnings + 1))
  fi
fi

# --- Container checks (only if running) ---
if $container_running; then
  $JSON_MODE || echo ""
  $JSON_MODE || echo "=== R environment (container) ==="
  $JSON_MODE || echo ""

  # R version
  r_ver=$($RUNTIME exec "$CONTAINER_NAME" Rscript -e "cat(paste(R.version\$major, R.version\$minor, sep='.'))" 2>/dev/null | tail -1)
  r_ver="${r_ver:-unknown}"
  if [[ "$r_ver" != "unknown" ]]; then
    if printf '%s\n%s\n' "$MIN_R_VERSION" "$r_ver" | sort -V | head -1 | grep -q "^${MIN_R_VERSION}$"; then
      record "R $r_ver (>= $MIN_R_VERSION)" "ok"
    else
      record "R $r_ver (need >= $MIN_R_VERSION)" "fail"
      errors=$((errors + 1))
    fi
  else
    record "R version" "fail" "could not detect"
    errors=$((errors + 1))
  fi

  # renv status
  if $RUNTIME exec -w /home/rstudio/bridle "$CONTAINER_NAME" \
      Rscript -e "cat(requireNamespace('renv', quietly = TRUE))" 2>/dev/null \
      | tail -1 | grep -q TRUE; then
    record "renv" "ok"
  else
    record "renv" "fail" "not installed in container"
    errors=$((errors + 1))
  fi

  # renv sync status (capture text output; "No issues found" means clean)
  renv_ok=$($RUNTIME exec -w /home/rstudio/bridle "$CONTAINER_NAME" \
      Rscript -e "out <- capture.output(renv::status(dev=TRUE)); cat(any(grepl('No issues found', out)))" 2>/dev/null \
      | tail -1)
  if [[ "$renv_ok" == "TRUE" ]]; then
    record "renv sync" "ok"
  else
    record "renv sync" "warn" "out of sync (run 'make renv-snapshot' or 'renv::status()' for details)"
    warnings=$((warnings + 1))
  fi

  # Required R packages
  for pkg in "${REQUIRED_R_PKGS[@]}"; do
    check_r_pkg "$pkg" true
  done

  # Optional R packages
  for pkg in "${OPTIONAL_R_PKGS[@]}"; do
    check_r_pkg "$pkg" false
  done
else
  $JSON_MODE || echo ""
  $JSON_MODE || echo "(Skipping R checks -- container not running)"
fi

# --- Summary ---
$JSON_MODE || echo ""

if $JSON_MODE; then
  items=$(IFS=,; echo "${results[*]}")
  printf '{"errors":%d,"warnings":%d,"runtime":"%s","checks":[%s]}\n' \
    "$errors" "$warnings" "$RUNTIME" "$items"
else
  echo "=== Summary ==="
  if [[ $errors -gt 0 ]]; then
    printf '\033[0;31m%d critical issue(s), %d warning(s)\033[0m\n' "$errors" "$warnings"
  elif [[ $warnings -gt 0 ]]; then
    printf '\033[1;33m0 critical issues, %d warning(s)\033[0m\n' "$warnings"
  else
    printf '\033[0;32mAll checks passed\033[0m\n'
  fi
fi

exit $( [[ $errors -gt 0 ]] && echo 1 || echo 0 )
