#!/usr/bin/env bash
# test-helpers.sh - Unit tests for codex-helpers.sh
#
# Usage:
#   ./scripts/test-helpers.sh           # Run all tests
#   ./scripts/test-helpers.sh --tmux    # Include tmux-dependent tests (requires tmux session)

set -e -u -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HELPERS="$SCRIPT_DIR/codex-helpers.sh"

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
# Test: Source helpers
# ==============================================================================
test_source_helpers() {
  echo "=== Testing: Source helpers ==="

  if [ ! -f "$HELPERS" ]; then
    fail "source helpers" "File not found: $HELPERS"
    return 1
  fi

  # shellcheck source=codex-helpers.sh
  source "$HELPERS"

  if [ "$_CODEX_HELPERS_LOADED" = "1" ]; then
    pass "source helpers"
  else
    fail "source helpers" "_CODEX_HELPERS_LOADED not set"
  fi
}

# ==============================================================================
# Test: codex_hash_content
# ==============================================================================
test_hash_content() {
  echo ""
  echo "=== Testing: codex_hash_content ==="

  # Test basic hashing
  local result
  result=$(echo "test" | codex_hash_content)

  if [ -n "$result" ] && [ ${#result} -eq 32 ]; then
    pass "hash_content returns 32-char hash"
  else
    fail "hash_content" "Expected 32-char hash, got: '$result' (${#result} chars)"
  fi

  # Test consistency
  local hash1 hash2
  hash1=$(echo "same content" | codex_hash_content)
  hash2=$(echo "same content" | codex_hash_content)

  if [ "$hash1" = "$hash2" ]; then
    pass "hash_content is consistent"
  else
    fail "hash_content consistency" "hash1='$hash1' != hash2='$hash2'"
  fi

  # Test different inputs produce different hashes
  local hash_a hash_b
  hash_a=$(echo "content A" | codex_hash_content)
  hash_b=$(echo "content B" | codex_hash_content)

  if [ "$hash_a" != "$hash_b" ]; then
    pass "hash_content produces different hashes for different inputs"
  else
    fail "hash_content differentiation" "Same hash for different inputs"
  fi
}

# ==============================================================================
# Test: codex_generate_signal
# ==============================================================================
test_generate_signal() {
  echo ""
  echo "=== Testing: codex_generate_signal ==="

  # Test with prefix
  local result
  result=$(codex_generate_signal "test-prefix")

  if [[ "$result" =~ ^test-prefix-[0-9]+-[0-9]+-[0-9]+$ ]]; then
    pass "generate_signal with prefix"
  else
    fail "generate_signal with prefix" "Got: '$result'"
  fi

  # Test default prefix
  result=$(codex_generate_signal)

  if [[ "$result" =~ ^codex-[0-9]+-[0-9]+-[0-9]+$ ]]; then
    pass "generate_signal default prefix"
  else
    fail "generate_signal default prefix" "Got: '$result'"
  fi

  # Test uniqueness
  local sig1 sig2
  sig1=$(codex_generate_signal "unique")
  sleep 0.1
  sig2=$(codex_generate_signal "unique")

  if [ "$sig1" != "$sig2" ]; then
    pass "generate_signal produces unique values"
  else
    fail "generate_signal uniqueness" "sig1='$sig1' == sig2='$sig2'"
  fi
}

# ==============================================================================
# Test: codex_check_tmux
# ==============================================================================
test_check_tmux() {
  echo ""
  echo "=== Testing: codex_check_tmux ==="

  if [ -n "${TMUX:-}" ]; then
    if codex_check_tmux 2>/dev/null; then
      pass "check_tmux returns success in tmux"
    else
      fail "check_tmux" "Should return success inside tmux"
    fi
  else
    if codex_check_tmux 2>/dev/null; then
      fail "check_tmux" "Should return failure outside tmux"
    else
      pass "check_tmux returns failure outside tmux"
    fi
  fi
}

# ==============================================================================
# Test: codex_verify_pane (requires tmux)
# ==============================================================================
test_verify_pane() {
  echo ""
  echo "=== Testing: codex_verify_pane ==="

  if [ -z "${TMUX:-}" ]; then
    skip "verify_pane" "Not in tmux session"
    return
  fi

  # Test with empty pane ID (use || true to prevent set -e exit)
  local result
  result=$(codex_verify_pane "" 2>/dev/null) || true
  if [ "$result" = "error:empty_pane_id" ]; then
    pass "verify_pane rejects empty pane ID"
  else
    fail "verify_pane empty" "Expected 'error:empty_pane_id', got '$result'"
  fi

  # Test with non-existent pane
  result=$(codex_verify_pane "%99999" 2>/dev/null) || true
  if [ "$result" = "error:pane_not_found" ]; then
    pass "verify_pane handles non-existent pane"
  else
    fail "verify_pane non-existent" "Expected 'error:pane_not_found', got '$result'"
  fi

  # Test with current pane (likely not Codex)
  local current_pane
  current_pane=$(tmux display-message -p '#{pane_id}')
  result=$(codex_verify_pane "$current_pane" 2>/dev/null) || true
  # Current pane is running bash/zsh, not Codex
  if [ "$result" = "error:not_codex_pane" ] || [ "$result" = "valid" ]; then
    pass "verify_pane checks current pane"
  else
    fail "verify_pane current" "Unexpected result: '$result'"
  fi
}

# ==============================================================================
# Test: codex_find_pane (requires tmux)
# ==============================================================================
test_find_pane() {
  echo ""
  echo "=== Testing: codex_find_pane ==="

  if [ -z "${TMUX:-}" ]; then
    skip "find_pane" "Not in tmux session"
    return
  fi

  # Create temp directory for test
  local test_dir
  test_dir=$(mktemp -d)
  local test_pane_file="$test_dir/.codex-pane-id"

  # Test with non-existent pane file (should search)
  local result
  result=$(codex_find_pane "$test_pane_file" 2>&1) || true
  # Should either find a Codex pane or report not found
  # Valid outputs: "No Codex pane found", "Auto-detected", "Found Codex", "Multiple Codex panes"
  if echo "$result" | grep -qE "(No Codex pane found|Auto-detected|Found Codex|Multiple Codex panes|scanning)"; then
    pass "find_pane handles missing pane file"
  else
    fail "find_pane missing file" "Unexpected output: '$result'"
  fi

  # Test with invalid stored pane ID
  echo "%99999" > "$test_pane_file"
  result=$(codex_find_pane "$test_pane_file" 2>&1) || true
  if echo "$result" | grep -qE "(invalid|scanning|No Codex pane)"; then
    pass "find_pane handles invalid stored ID"
  else
    fail "find_pane invalid ID" "Unexpected output: '$result'"
  fi

  # Cleanup
  rm -rf "$test_dir"
}

# ==============================================================================
# Test: codex_send_prompt (requires tmux, mock only)
# ==============================================================================
test_send_prompt() {
  echo ""
  echo "=== Testing: codex_send_prompt ==="

  if [ -z "${TMUX:-}" ]; then
    skip "send_prompt" "Not in tmux session"
    return
  fi

  # Test with empty arguments
  local result
  result=$(codex_send_prompt "" "" 2>&1) || true
  if echo "$result" | grep -qE "required|error|Error"; then
    pass "send_prompt validates arguments"
  else
    fail "send_prompt validation" "Should reject empty arguments, got: '$result'"
  fi

  # Note: Full test requires a Codex pane, skipping interactive test
  skip "send_prompt full" "Requires active Codex pane"
}

# ==============================================================================
# Test: codex_wait_completion (mock only)
# ==============================================================================
test_wait_completion() {
  echo ""
  echo "=== Testing: codex_wait_completion ==="

  # This is difficult to test without a real Codex pane
  # Just verify the function exists and accepts arguments
  if type codex_wait_completion &>/dev/null; then
    pass "wait_completion function exists"
  else
    fail "wait_completion" "Function not defined"
  fi

  skip "wait_completion full" "Requires active Codex pane"
}

# ==============================================================================
# Test: codex_capture_output (requires tmux)
# ==============================================================================
test_capture_output() {
  echo ""
  echo "=== Testing: codex_capture_output ==="

  if [ -z "${TMUX:-}" ]; then
    skip "capture_output" "Not in tmux session"
    return
  fi

  # Test capturing current pane
  local test_file
  test_file=$(mktemp)
  local current_pane
  current_pane=$(tmux display-message -p '#{pane_id}')

  local result
  result=$(codex_capture_output "$current_pane" "$test_file")

  if [ -f "$test_file" ] && [ -s "$test_file" ]; then
    pass "capture_output creates file with content"
  else
    fail "capture_output" "File not created or empty"
  fi

  # Cleanup
  rm -f "$test_file"
}

# ==============================================================================
# Test: Multiple sourcing guard
# ==============================================================================
test_multiple_source() {
  echo ""
  echo "=== Testing: Multiple source guard ==="

  # Reset the guard
  unset _CODEX_HELPERS_LOADED

  # Source twice
  source "$HELPERS"
  local first_load="$_CODEX_HELPERS_LOADED"
  source "$HELPERS"
  local second_load="$_CODEX_HELPERS_LOADED"

  if [ "$first_load" = "1" ] && [ "$second_load" = "1" ]; then
    pass "multiple source guard works"
  else
    fail "multiple source guard" "first=$first_load, second=$second_load"
  fi
}

# ==============================================================================
# Main
# ==============================================================================
main() {
  echo "codex-helpers.sh Test Suite"
  echo "============================"
  echo ""

  # Check if --tmux flag is passed
  local include_tmux=false
  if [ "${1:-}" = "--tmux" ]; then
    include_tmux=true
  fi

  # Run tests
  test_source_helpers
  test_hash_content
  test_generate_signal
  test_check_tmux
  test_multiple_source

  # tmux-dependent tests
  if [ "$include_tmux" = true ] || [ -n "${TMUX:-}" ]; then
    test_verify_pane
    test_find_pane
    test_send_prompt
    test_wait_completion
    test_capture_output
  else
    echo ""
    echo "=== Skipping tmux-dependent tests ==="
    echo "(Run with --tmux inside a tmux session for full tests)"
    ((SKIP+=5))
  fi

  # Summary
  echo ""
  echo "============================"
  echo "Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}, ${YELLOW}$SKIP skipped${NC}"
  echo ""

  # Exit with failure if any tests failed
  [ "$FAIL" -eq 0 ]
}

main "$@"
