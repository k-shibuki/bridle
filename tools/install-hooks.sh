#!/usr/bin/env bash
# tools/install-hooks.sh -- Install guard hooks directly into .git/hooks/
#
# Installs lightweight bash hook scripts that enforce Hard Stops without
# requiring the pre-commit framework or Rscript on the host.
#
# Guard hooks installed:
#   commit-msg  → tools/check-commit-msg.sh  (HS-NOLINT: commit message format)
#   pre-commit  → tools/check-nolint.sh      (HS-NOLINT: nolint annotation format)
#   pre-push    → tools/pre-push.sh          (HS-LOCAL-VERIFY: local verification gate)
#
# R-based quality hooks (style, lint, roxygen) are handled by make targets
# inside the container and by CI — they are NOT installed on the host.
#
# Usage: bash tools/install-hooks.sh [--force]
set -euo pipefail

HOOK_DIR="$(git rev-parse --git-dir)/hooks"
MARKER="# bridle-guard-hook"
FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

installed=0
skipped=0

install_hook() {
  local hook_type="$1"
  local content="$2"
  local target="$HOOK_DIR/$hook_type"

  if [[ -f "$target" ]]; then
    if grep -q "$MARKER" "$target" 2>/dev/null; then
      if $FORCE; then
        echo "  Overwriting $hook_type (--force)"
      else
        skipped=$((skipped + 1))
        return 0
      fi
    else
      echo "  WARNING: $target exists but is not a bridle guard hook."
      echo "           Use --force to overwrite, or remove it manually."
      skipped=$((skipped + 1))
      return 0
    fi
  fi

  printf '%s' "$content" > "$target"
  chmod +x "$target"
  installed=$((installed + 1))
}

mkdir -p "$HOOK_DIR"

# --- commit-msg hook ---
install_hook "commit-msg" "#!/usr/bin/env bash
${MARKER}: commit message format validator
exec bash tools/check-commit-msg.sh \"\$1\"
"

# --- pre-commit hook ---
install_hook "pre-commit" "#!/usr/bin/env bash
${MARKER}: nolint annotation validator
set -euo pipefail

staged_r=\$(git diff --cached --name-only --diff-filter=ACM -- \"*.R\" \"*.r\") || true
if [[ -n \"\$staged_r\" ]]; then
  echo \"\$staged_r\" | xargs bash tools/check-nolint.sh
fi
"

# --- pre-push hook ---
install_hook "pre-push" "#!/usr/bin/env bash
${MARKER}: pre-push verification gate
exec bash tools/pre-push.sh
"

if [[ $installed -gt 0 ]]; then
  echo "Installed $installed guard hook(s)."
fi
if [[ $skipped -gt 0 && $installed -gt 0 ]]; then
  echo "Skipped $skipped hook(s) (already installed)."
fi
