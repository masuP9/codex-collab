#!/usr/bin/env bash
# test-enforce-skill-usage.sh - Unit tests for enforce-skill-usage.sh hook
#
# Usage:
#   bash hooks/test-enforce-skill-usage.sh

set -e -u -o pipefail

HOOK="$(cd "$(dirname "$0")" && pwd)/enforce-skill-usage.sh"

# Test counters
PASS=0
FAIL=0
SKIP=0

# Colors (if terminal supports)
if [ -t 1 ]; then
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  YELLOW='\033[0;33m'
  NC='\033[0m' # No Color
else
  GREEN=''
  RED=''
  YELLOW=''
  NC=''
fi

# Test utilities
pass() {
  echo -e "${GREEN}✓${NC} $1"
  PASS=$((PASS + 1))
}

fail() {
  echo -e "${RED}✗${NC} $1: $2"
  FAIL=$((FAIL + 1))
}

skip() {
  echo -e "${YELLOW}○${NC} $1: skipped ($2)"
  SKIP=$((SKIP + 1))
}

# ==============================================================================
# Helper
# ==============================================================================

# run_hook "<command string>" → runs the hook and returns its exit code
run_hook() {
  printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$1" | jq -Rs .)" \
    | bash "$HOOK" >/dev/null 2>&1
  echo $?
}

# ==============================================================================
# Tests
# ==============================================================================

echo "=== Testing: enforce-skill-usage.sh ==="

# Case 1: irrelevant command — should be allowed (exit 0)
result=$(run_hook 'ls -la')
if [ "$result" = "0" ]; then
  pass "case 1: irrelevant command (ls -la) is allowed"
else
  fail "case 1: irrelevant command (ls -la) is allowed" "expected exit 0, got $result"
fi

# Case 2: direct helper call — should be blocked (exit 2)
result=$(run_hook 'codex_run_exec prompt.txt')
if [ "$result" = "2" ]; then
  pass "case 2: direct codex_run_exec call is blocked"
else
  fail "case 2: direct codex_run_exec call is blocked" "expected exit 2, got $result"
fi

# Case 3: source codex-helpers.sh — should be blocked (exit 2)
result=$(run_hook 'source scripts/codex-helpers.sh')
if [ "$result" = "2" ]; then
  pass "case 3: 'source codex-helpers.sh' is blocked"
else
  fail "case 3: 'source codex-helpers.sh' is blocked" "expected exit 2, got $result"
fi

# Case 4: dot-source codex-helpers.sh — should be blocked (exit 2)
result=$(run_hook '. ./scripts/codex-helpers.sh')
if [ "$result" = "2" ]; then
  pass "case 4: '. ./scripts/codex-helpers.sh' is blocked"
else
  fail "case 4: '. ./scripts/codex-helpers.sh' is blocked" "expected exit 2, got $result"
fi

# Case 5: HELPERS= assignment — should be blocked (exit 2)
result=$(run_hook 'HELPERS=scripts/codex-helpers.sh')
if [ "$result" = "2" ]; then
  pass "case 5: 'HELPERS=...codex-helpers.sh' assignment is blocked"
else
  fail "case 5: 'HELPERS=...codex-helpers.sh' assignment is blocked" "expected exit 2, got $result"
fi

# Case 6: skill context marker present — should be allowed even with helper call (exit 0)
result=$(run_hook 'export CODEX_SKILL_CONTEXT=1; codex_run_exec x')
if [ "$result" = "0" ]; then
  pass "case 6: CODEX_SKILL_CONTEXT=1 marker allows helper calls"
else
  fail "case 6: CODEX_SKILL_CONTEXT=1 marker allows helper calls" "expected exit 0, got $result"
fi

# Case 7: CODEX_PROMPT reference — should be blocked (exit 2)
# shellcheck disable=SC2016 # $CODEX_PROMPT is a literal string fed to the hook, not a shell variable
result=$(run_hook 'echo $CODEX_PROMPT')
if [ "$result" = "2" ]; then
  pass "case 7: CODEX_PROMPT pattern is blocked"
else
  fail "case 7: CODEX_PROMPT pattern is blocked" "expected exit 2, got $result"
fi

# Case 8: empty JSON {} (no command key) — fail open (exit 0)
result=$(echo '{}' | bash "$HOOK" >/dev/null 2>&1; echo $?)
if [ "$result" = "0" ]; then
  pass "case 8: empty JSON {} fails open (allowed)"
else
  fail "case 8: empty JSON {} fails open (allowed)" "expected exit 0, got $result"
fi

# Case 9: invalid JSON — fail open (exit 0)
result=$(echo 'not-json' | bash "$HOOK" >/dev/null 2>&1; echo $?)
if [ "$result" = "0" ]; then
  pass "case 9: invalid JSON fails open (allowed)"
else
  fail "case 9: invalid JSON fails open (allowed)" "expected exit 0, got $result"
fi

# Case 10: plain codex CLI invocation (no codex_ prefix) — should be allowed (exit 0)
result=$(run_hook 'codex exec -s read-only - < p.txt')
if [ "$result" = "0" ]; then
  pass "case 10: plain 'codex exec' (no codex_ prefix) is allowed"
else
  fail "case 10: plain 'codex exec' (no codex_ prefix) is allowed" "expected exit 0, got $result"
fi

# Case 11: gh pr create with a function name in the title argument — blocked (exit 2)
# NOTE: 既知の誤検知を固定化（パターン改善時はこの期待値を 0 に変える）
# The pattern \bcodex_[A-Za-z0-9_]+\b matches function names in argument text, not just
# direct calls. Real incident: gh pr create --body "..." containing codex_strip_ansi was
# blocked during PR #56 (2026-06-12). Workaround was --body-file. Pattern fix is out of
# scope for this plan.
result=$(run_hook 'gh pr create --body-file body.md --title "fix codex_strip_ansi"')
if [ "$result" = "2" ]; then
  pass "case 11: function name in gh pr title triggers block (known false positive, characterization)"
else
  fail "case 11: function name in gh pr title triggers block (known false positive, characterization)" "expected exit 2, got $result"
fi

# ==============================================================================
# Summary
# ==============================================================================
echo ""
echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
