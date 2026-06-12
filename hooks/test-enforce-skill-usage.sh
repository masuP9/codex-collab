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

# Case 3: source codex-helpers.sh — now allowed (exit 0), not a side-effect helper (縮小により非対象)
result=$(run_hook 'source scripts/codex-helpers.sh')
if [ "$result" = "0" ]; then
  pass "case 3: 'source codex-helpers.sh' is allowed (narrowed scope — not a side-effect helper)"
else
  fail "case 3: 'source codex-helpers.sh' is allowed (narrowed scope — not a side-effect helper)" "expected exit 0, got $result"
fi

# Case 4: dot-source codex-helpers.sh — now allowed (exit 0), not a side-effect helper (縮小により非対象)
result=$(run_hook '. ./scripts/codex-helpers.sh')
if [ "$result" = "0" ]; then
  pass "case 4: '. ./scripts/codex-helpers.sh' is allowed (narrowed scope — not a side-effect helper)"
else
  fail "case 4: '. ./scripts/codex-helpers.sh' is allowed (narrowed scope — not a side-effect helper)" "expected exit 0, got $result"
fi

# Case 5: HELPERS= assignment — now allowed (exit 0), not a side-effect helper (縮小により非対象)
result=$(run_hook 'HELPERS=scripts/codex-helpers.sh')
if [ "$result" = "0" ]; then
  pass "case 5: 'HELPERS=...codex-helpers.sh' assignment is allowed (narrowed scope — not a side-effect helper)"
else
  fail "case 5: 'HELPERS=...codex-helpers.sh' assignment is allowed (narrowed scope — not a side-effect helper)" "expected exit 0, got $result"
fi

# Case 6: skill context marker present — should be allowed even with helper call (exit 0)
result=$(run_hook 'export CODEX_SKILL_CONTEXT=1; codex_run_exec x')
if [ "$result" = "0" ]; then
  pass "case 6: CODEX_SKILL_CONTEXT=1 marker allows helper calls"
else
  fail "case 6: CODEX_SKILL_CONTEXT=1 marker allows helper calls" "expected exit 0, got $result"
fi

# Case 7: CODEX_PROMPT reference — now allowed (exit 0), speculative pattern removed (縮小により非対象)
# shellcheck disable=SC2016 # $CODEX_PROMPT is a literal string fed to the hook, not a shell variable
result=$(run_hook 'echo $CODEX_PROMPT')
if [ "$result" = "0" ]; then
  pass "case 7: CODEX_PROMPT reference is allowed (narrowed scope — speculative pattern intentionally removed)"
else
  fail "case 7: CODEX_PROMPT reference is allowed (narrowed scope — speculative pattern intentionally removed)" "expected exit 0, got $result"
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
# shellcheck disable=SC2016 # literal command string for the hook (single-quoted intentionally, $(...) must not expand)
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

# Case 16: codex_strip_ansi as pipe target — now allowed (exit 0), pure transform is non-target (縮小により非対象)
result=$(run_hook 'cat out.txt | codex_strip_ansi')
if [ "$result" = "0" ]; then
  pass "case 16: codex_strip_ansi as pipe target is allowed (narrowed scope — pure transform, not a side-effect helper)"
else
  fail "case 16: codex_strip_ansi as pipe target is allowed (narrowed scope — pure transform, not a side-effect helper)" "expected exit 0, got $result"
fi

# Case 17: multiline command with helper on second line — blocked (exit 2)
# Line-start anchor must fire on each line of a multiline command.
result=$(run_hook "$(printf 'echo start\ncodex_run_exec x')")
if [ "$result" = "2" ]; then
  pass "case 17: helper call at line start in multiline command is blocked"
else
  fail "case 17: helper call at line start in multiline command is blocked" "expected exit 2, got $result"
fi

# Case 18: codex_run_review as pipe target — blocked (exit 2)
# Side-effect helper in pipe target must still be detected (旧ケース16の対象関数版).
result=$(run_hook 'cat out.txt | codex_run_review')
if [ "$result" = "2" ]; then
  pass "case 18: codex_run_review as pipe target is blocked (side-effect helper)"
else
  fail "case 18: codex_run_review as pipe target is blocked (side-effect helper)" "expected exit 2, got $result"
fi

# Case 19: codex_strip_ansi at line start — allowed (exit 0)
# Non-target helper at line start must not be blocked.
result=$(run_hook 'codex_strip_ansi < raw.txt')
if [ "$result" = "0" ]; then
  pass "case 19: codex_strip_ansi at line start is allowed (pure transform, non-target)"
else
  fail "case 19: codex_strip_ansi at line start is allowed (pure transform, non-target)" "expected exit 0, got $result"
fi

# Case 20: codex_save_thread at line start — blocked (exit 2)
# State-write helper at line start must be detected.
result=$(run_hook 'codex_save_thread t1 thread-x')
if [ "$result" = "2" ]; then
  pass "case 20: codex_save_thread at line start is blocked (state-write helper)"
else
  fail "case 20: codex_save_thread at line start is blocked (state-write helper)" "expected exit 2, got $result"
fi

# Case 21: CODEX_SKILL_CONTEXT=1 in echo (not line-start export) — blocked (exit 2)
# Substring mention of marker does not bypass the guard; only line-start export does.
result=$(run_hook 'echo "CODEX_SKILL_CONTEXT=1"; codex_run_exec x')
if [ "$result" = "2" ]; then
  pass "case 21: substring marker mention (in echo) does not bypass the guard"
else
  fail "case 21: substring marker mention (in echo) does not bypass the guard" "expected exit 2, got $result"
fi

# Case 22: multiline with comment then line-start export — allowed (exit 0)
# Comment line followed by line-start 'export CODEX_SKILL_CONTEXT=1' must be recognized
# (this is the real shape of commands/*.md bash blocks).
result=$(run_hook "$(printf '# setup\nexport CODEX_SKILL_CONTEXT=1\ncodex_run_exec x')")
if [ "$result" = "0" ]; then
  pass "case 22: comment + line-start export CODEX_SKILL_CONTEXT=1 is allowed (commands/*.md real shape)"
else
  fail "case 22: comment + line-start export CODEX_SKILL_CONTEXT=1 is allowed (commands/*.md real shape)" "expected exit 0, got $result"
fi

# ==============================================================================
# Summary
# ==============================================================================
echo ""
echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
