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

# Case 11: gh pr create with a function name in the title argument — allowed (exit 0)
# NOTE: パターン改善（Plan 006）により引数テキスト中の言及は許可される。
# The pattern now anchors to execution positions (line start, after ; & |, inside $(...) or backticks),
# so function names appearing only in argument text (commit messages, PR bodies, grep patterns)
# are no longer blocked. Real incident: gh pr create --body "..." containing a function name
# was blocked during PR #56 (2026-06-12). This is now correctly allowed.
result=$(run_hook 'gh pr create --body-file body.md --title "fix codex_strip_ansi"')
if [ "$result" = "0" ]; then
  pass "case 11: function name in gh pr title is allowed (false positive fixed)"
else
  fail "case 11: function name in gh pr title is allowed (false positive fixed)" "expected exit 0, got $result"
fi

# Case 12: git commit with function name in message — allowed (exit 0)
# Incident 3 reproduction: commit messages mentioning helper names should not be blocked.
result=$(run_hook 'git commit -m "fix: harden codex_json_escape handling"')
if [ "$result" = "0" ]; then
  pass "case 12: function name in git commit message is allowed"
else
  fail "case 12: function name in git commit message is allowed" "expected exit 0, got $result"
fi

# Case 13: grep for function name in source file — allowed (exit 0)
# Incident 2 reproduction: grepping for a helper name should not be blocked.
result=$(run_hook "grep -n 'codex_json_escape()' scripts/codex-helpers.sh")
if [ "$result" = "0" ]; then
  pass "case 13: function name in grep pattern is allowed"
else
  fail "case 13: function name in grep pattern is allowed" "expected exit 0, got $result"
fi

# Case 14: command substitution with helper call — blocked (exit 2)
# Execution inside $(...) must still be detected.
result=$(run_hook 'v=$(codex_run_exec x)')
if [ "$result" = "2" ]; then
  pass "case 14: helper call inside command substitution is blocked"
else
  fail "case 14: helper call inside command substitution is blocked" "expected exit 2, got $result"
fi

# Case 15: helper call after && — blocked (exit 2)
# Execution after logical-and operator must still be detected.
result=$(run_hook 'true && codex_run_exec x')
if [ "$result" = "2" ]; then
  pass "case 15: helper call after && is blocked"
else
  fail "case 15: helper call after && is blocked" "expected exit 2, got $result"
fi

# Case 16: helper call as pipe target — blocked (exit 2)
# Execution as a pipeline target must still be detected.
result=$(run_hook 'cat out.txt | codex_strip_ansi')
if [ "$result" = "2" ]; then
  pass "case 16: helper call as pipe target is blocked"
else
  fail "case 16: helper call as pipe target is blocked" "expected exit 2, got $result"
fi

# Case 17: multiline command with helper on second line — blocked (exit 2)
# Line-start anchor must fire on each line of a multiline command.
result=$(run_hook "$(printf 'echo start\ncodex_run_exec x')")
if [ "$result" = "2" ]; then
  pass "case 17: helper call at line start in multiline command is blocked"
else
  fail "case 17: helper call at line start in multiline command is blocked" "expected exit 2, got $result"
fi

# ==============================================================================
# Summary
# ==============================================================================
echo ""
echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
