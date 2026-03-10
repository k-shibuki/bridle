#!/bin/sh
# test-review-sync-check.sh — Regression tests for review-sync-check.sh
#
# Creates temporary fixture files and verifies the sync-check script
# detects drift correctly, including patterns with spaces.
#
# Usage: sh tools/test-review-sync-check.sh

set -e

SCRIPT="tools/review-sync-check.sh"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0

assert_exit() {
  test_name="$1"
  expected="$2"
  actual="$3"
  if [ "$expected" -eq "$actual" ]; then
    echo "  PASS: $test_name"
    pass=$((pass + 1))
  else
    echo "  FAIL: $test_name (expected exit $expected, got $actual)"
    fail=$((fail + 1))
  fi
}

# --- Fixture generators ---

make_agents() {
  cat > "$TMPDIR/AGENTS.md" << 'FIXTURE'
# Review guidelines

### S7 type safety (P0)
Every S7 property MUST have an explicit type.

### Test quality (P0 if missing)
Flag as P0 if changed code has no corresponding tests.

### Traceability (P1)
PR body must contain `Closes #<issue>` or `Fixes #<issue>`.
Commit messages should include `Refs: #<issue>` in the footer.

### Architecture and ADR compliance (P1)
Changes to domain classes must follow ADR-0001.

### Security (P0)
Flag any changes involving authentication or authorization logic.

### Code quality
Watch for readability, naming, duplication issues.
FIXTURE
}

make_pr_review() {
  cat > "$TMPDIR/pr-review.md" << 'FIXTURE'
# pr-review

| Category | What to check |
|---------|---------------|
| **Type safety** | S7 properties have explicit types |
| **Test quality** | test matrix exists |
| **Traceability** | `Closes #<issue>` present, `Refs: #<issue>` in commits |
| **Spec alignment** | aligns with ADRs |
| **Security** | authentication, authorization flagged |
| **Code quality** | readability, naming, duplication |
FIXTURE
}

# Run the script against fixture files by overriding AGENTS_FILE and PR_REVIEW_FILE.
# The script uses these variables internally; we cd into TMPDIR and create
# symlink-free copies so relative paths resolve.
run_check() {
  (
    cd "$TMPDIR"
    AGENTS_FILE="AGENTS.md" PR_REVIEW_FILE="pr-review.md" \
      sh "$OLDPWD/$SCRIPT" > stdout.txt 2> stderr.txt
  )
}

# --- Tests ---

echo "=== Test 1: Both files in sync ==="
make_agents
make_pr_review
set +e; run_check; rc=$?; set -e
assert_exit "baseline sync" 0 "$rc"

echo ""
echo "=== Test 2: Traceability removed from pr-review.md ==="
make_agents
make_pr_review
# Remove all traceability signals
sed -i '/[Tt]raceability/d; /Closes #/d; /Refs: #/d; /Refs:#/d' "$TMPDIR/pr-review.md"
set +e; run_check; rc=$?; set -e
assert_exit "traceability drift detected" 1 "$rc"

echo ""
echo "=== Test 3: Security removed from AGENTS.md ==="
make_agents
make_pr_review
sed -i '/[Ss]ecurity/d; /[Aa]uthenti/d; /[Aa]uthoriz/d' "$TMPDIR/AGENTS.md"
set +e; run_check; rc=$?; set -e
assert_exit "security drift detected" 1 "$rc"

echo ""
echo "=== Test 4: Space-containing pattern 'Closes #' works ==="
make_agents
make_pr_review
# Keep Traceability row but strip "Closes #" and "Refs: #" specifically
sed -i 's/Closes #[^|]*/REDACTED/g; s/Refs: #[^|]*/REDACTED/g' "$TMPDIR/pr-review.md"
# Also remove the word "traceability" so only the redacted row remains
sed -i '/[Tt]raceability/d' "$TMPDIR/pr-review.md"
set +e; run_check; rc=$?; set -e
assert_exit "space-pattern drift detected" 1 "$rc"

echo ""
echo "=== Test 5: AGENTS.md missing (skip gracefully) ==="
rm -f "$TMPDIR/AGENTS.md"
make_pr_review
set +e; run_check; rc=$?; set -e
assert_exit "missing AGENTS.md skips" 0 "$rc"

echo ""
echo "=== Test 6: pr-review.md missing (error) ==="
make_agents
rm -f "$TMPDIR/pr-review.md"
set +e; run_check; rc=$?; set -e
assert_exit "missing pr-review.md errors" 1 "$rc"

echo ""
echo "================================="
echo "Results: $pass passed, $fail failed"
if [ "$fail" -gt 0 ]; then
  exit 1
fi
