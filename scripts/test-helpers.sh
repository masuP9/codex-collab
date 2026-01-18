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
# Test: codex_ensure_tmp_dir and codex_tmp_path
# ==============================================================================
test_tmp_directory() {
  echo ""
  echo "=== Testing: codex_ensure_tmp_dir / codex_tmp_path ==="

  # Save original value
  local orig_tmp_dir="${CODEX_TMP_DIR:-}"

  # Use relative path for test (matching spec: relative paths only)
  local test_tmp=".test-tmp-$$"
  CODEX_TMP_DIR="$test_tmp"

  # Clean up any existing test directory
  rm -rf "$test_tmp"

  # Test codex_ensure_tmp_dir creates directory
  local result
  result=$(codex_ensure_tmp_dir)
  if [ -d "$test_tmp" ]; then
    pass "ensure_tmp_dir creates directory"
  else
    fail "ensure_tmp_dir" "Directory not created: $test_tmp"
  fi

  # Test codex_ensure_tmp_dir returns path
  if [ "$result" = "$test_tmp" ]; then
    pass "ensure_tmp_dir returns correct path"
  else
    fail "ensure_tmp_dir return" "Expected '$test_tmp', got '$result'"
  fi

  # Test codex_tmp_path returns correct path
  local path_result
  path_result=$(codex_tmp_path "test-file.txt")
  if [ "$path_result" = "$test_tmp/test-file.txt" ]; then
    pass "tmp_path returns correct path"
  else
    fail "tmp_path" "Expected '$test_tmp/test-file.txt', got '$path_result'"
  fi

  # Cleanup
  rm -rf "$test_tmp"
  CODEX_TMP_DIR="$orig_tmp_dir"
}

# ==============================================================================
# Test: codex_tmux_cmd
# ==============================================================================
test_tmux_cmd() {
  echo ""
  echo "=== Testing: codex_tmux_cmd ==="

  # Save original value
  local orig_socket="${CODEX_TMUX_SOCKET:-}"

  # Test without socket
  CODEX_TMUX_SOCKET=""
  local result
  result=$(codex_tmux_cmd)
  if [ "$result" = "tmux" ]; then
    pass "tmux_cmd without socket"
  else
    fail "tmux_cmd without socket" "Expected 'tmux', got '$result'"
  fi

  # Test with socket
  CODEX_TMUX_SOCKET="./test.sock"
  result=$(codex_tmux_cmd)
  if [ "$result" = "tmux -S ./test.sock" ]; then
    pass "tmux_cmd with socket"
  else
    fail "tmux_cmd with socket" "Expected 'tmux -S ./test.sock', got '$result'"
  fi

  # Restore
  CODEX_TMUX_SOCKET="$orig_socket"
}

# ==============================================================================
# Test: codex_extract_metadata
# ==============================================================================
test_extract_metadata() {
  echo ""
  echo "=== Testing: codex_extract_metadata ==="

  # Test with valid metadata block
  local response1="Some response text here.

---
status: continue
verdict: pass
---"
  local meta1
  meta1=$(codex_extract_metadata "$response1")
  if echo "$meta1" | grep -q "status: continue"; then
    pass "extract_metadata finds metadata block"
  else
    fail "extract_metadata" "Failed to find metadata in: $meta1"
  fi

  # Test with no metadata block
  local response2="Just plain text without metadata."
  local meta2
  meta2=$(codex_extract_metadata "$response2")
  if [ -z "$meta2" ]; then
    pass "extract_metadata returns empty for no metadata"
  else
    fail "extract_metadata no metadata" "Expected empty, got: $meta2"
  fi

  # Test with multiple blocks (should get last)
  local response3="---
status: wrong
---
Middle text
---
status: correct
verdict: conditional
---"
  local meta3
  meta3=$(codex_extract_metadata "$response3")
  if echo "$meta3" | grep -q "status: correct"; then
    pass "extract_metadata gets last block"
  else
    fail "extract_metadata last block" "Got: $meta3"
  fi
}

# ==============================================================================
# Test: codex_get_field
# ==============================================================================
test_get_field() {
  echo ""
  echo "=== Testing: codex_get_field ==="

  local metadata="status: continue
verdict: pass
findings:
  - item 1"

  # Test getting simple field
  local status
  status=$(codex_get_field "$metadata" "status")
  if [ "$status" = "continue" ]; then
    pass "get_field extracts status"
  else
    fail "get_field status" "Expected 'continue', got '$status'"
  fi

  # Test getting another field
  local verdict
  verdict=$(codex_get_field "$metadata" "verdict")
  if [ "$verdict" = "pass" ]; then
    pass "get_field extracts verdict"
  else
    fail "get_field verdict" "Expected 'pass', got '$verdict'"
  fi

  # Test missing field
  local missing
  missing=$(codex_get_field "$metadata" "nonexistent")
  if [ -z "$missing" ]; then
    pass "get_field returns empty for missing field"
  else
    fail "get_field missing" "Expected empty, got '$missing'"
  fi
}

# ==============================================================================
# Test: codex_get_status
# ==============================================================================
test_get_status() {
  echo ""
  echo "=== Testing: codex_get_status ==="

  # Test valid status: continue
  local meta1="status: continue"
  local result1
  result1=$(codex_get_status "$meta1")
  if [ "$result1" = "continue" ]; then
    pass "get_status returns continue"
  else
    fail "get_status continue" "Expected 'continue', got '$result1'"
  fi

  # Test valid status: stop
  local meta2="status: stop"
  local result2
  result2=$(codex_get_status "$meta2")
  if [ "$result2" = "stop" ]; then
    pass "get_status returns stop"
  else
    fail "get_status stop" "Expected 'stop', got '$result2'"
  fi

  # Test invalid/missing status (defaults to stop)
  local meta3="verdict: pass"
  local result3
  result3=$(codex_get_status "$meta3")
  if [ "$result3" = "stop" ]; then
    pass "get_status defaults to stop"
  else
    fail "get_status default" "Expected 'stop', got '$result3'"
  fi
}

# ==============================================================================
# Test: codex_get_verdict
# ==============================================================================
test_get_verdict() {
  echo ""
  echo "=== Testing: codex_get_verdict ==="

  # Test pass
  local meta1="verdict: pass"
  local result1
  result1=$(codex_get_verdict "$meta1")
  if [ "$result1" = "pass" ]; then
    pass "get_verdict returns pass"
  else
    fail "get_verdict pass" "Expected 'pass', got '$result1'"
  fi

  # Test conditional
  local meta2="verdict: conditional"
  local result2
  result2=$(codex_get_verdict "$meta2")
  if [ "$result2" = "conditional" ]; then
    pass "get_verdict returns conditional"
  else
    fail "get_verdict conditional" "Expected 'conditional', got '$result2'"
  fi

  # Test fail
  local meta3="verdict: fail"
  local result3
  result3=$(codex_get_verdict "$meta3")
  if [ "$result3" = "fail" ]; then
    pass "get_verdict returns fail"
  else
    fail "get_verdict fail" "Expected 'fail', got '$result3'"
  fi

  # Test invalid verdict (returns empty)
  local meta4="verdict: invalid"
  local result4
  result4=$(codex_get_verdict "$meta4")
  if [ -z "$result4" ]; then
    pass "get_verdict returns empty for invalid"
  else
    fail "get_verdict invalid" "Expected empty, got '$result4'"
  fi
}

# ==============================================================================
# Test: codex_get_list
# ==============================================================================
test_get_list() {
  echo ""
  echo "=== Testing: codex_get_list ==="

  local metadata="status: continue
open_questions:
  - question one
  - question two
  - question three
decisions:
  - decision one"

  # Test extracting list
  local questions
  questions=$(codex_get_list "$metadata" "open_questions")
  local count
  count=$(echo "$questions" | grep -c "question" || true)
  if [ "$count" -eq 3 ]; then
    pass "get_list extracts all items"
  else
    fail "get_list count" "Expected 3 items, got $count"
  fi

  # Test first item
  local first
  first=$(echo "$questions" | head -1)
  if [ "$first" = "question one" ]; then
    pass "get_list preserves order"
  else
    fail "get_list order" "Expected 'question one', got '$first'"
  fi

  # Test empty list
  local empty
  empty=$(codex_get_list "$metadata" "nonexistent")
  if [ -z "$empty" ]; then
    pass "get_list returns empty for missing field"
  else
    fail "get_list missing" "Expected empty, got '$empty'"
  fi
}

# ==============================================================================
# Test: codex_extract_verdict_fallback
# ==============================================================================
test_extract_verdict_fallback() {
  echo ""
  echo "=== Testing: codex_extract_verdict_fallback ==="

  # Test PASS detection
  local response1="The review is complete. PASS - no issues found."
  local result1
  result1=$(codex_extract_verdict_fallback "$response1")
  if [ "$result1" = "pass" ]; then
    pass "extract_verdict_fallback detects PASS"
  else
    fail "extract_verdict_fallback PASS" "Expected 'pass', got '$result1'"
  fi

  # Test FAIL detection
  local response2="Critical issues found. FAIL"
  local result2
  result2=$(codex_extract_verdict_fallback "$response2")
  if [ "$result2" = "fail" ]; then
    pass "extract_verdict_fallback detects FAIL"
  else
    fail "extract_verdict_fallback FAIL" "Expected 'fail', got '$result2'"
  fi

  # Test CONDITIONAL detection
  local response3="Minor issues. CONDITIONAL approval."
  local result3
  result3=$(codex_extract_verdict_fallback "$response3")
  if [ "$result3" = "conditional" ]; then
    pass "extract_verdict_fallback detects CONDITIONAL"
  else
    fail "extract_verdict_fallback CONDITIONAL" "Expected 'conditional', got '$result3'"
  fi

  # Test no verdict
  local response4="Just some text without any verdict."
  local result4
  result4=$(codex_extract_verdict_fallback "$response4")
  if [ -z "$result4" ]; then
    pass "extract_verdict_fallback returns empty when no verdict"
  else
    fail "extract_verdict_fallback none" "Expected empty, got '$result4'"
  fi
}

# ==============================================================================
# Test: codex_parse_response
# ==============================================================================
test_parse_response() {
  echo ""
  echo "=== Testing: codex_parse_response ==="

  local response="This is the response body.
It has multiple lines.

---
status: continue
verdict: pass
---"

  codex_parse_response "$response"

  # Test metadata extraction
  if echo "$CODEX_RESPONSE_META" | grep -q "status: continue"; then
    pass "parse_response extracts metadata"
  else
    fail "parse_response meta" "Metadata not found: $CODEX_RESPONSE_META"
  fi

  # Test body extraction (should not contain metadata)
  if echo "$CODEX_RESPONSE_BODY" | grep -q "response body" && \
     ! echo "$CODEX_RESPONSE_BODY" | grep -q "status: continue"; then
    pass "parse_response extracts body"
  else
    fail "parse_response body" "Body incorrect: $CODEX_RESPONSE_BODY"
  fi

  # Cleanup
  unset CODEX_RESPONSE_BODY
  unset CODEX_RESPONSE_META
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

  # Run tests (no tmux required)
  test_source_helpers
  test_hash_content
  test_generate_signal
  test_check_tmux
  test_multiple_source
  test_tmp_directory
  test_tmux_cmd

  # Lightweight metadata extraction tests (no tmux required)
  test_extract_metadata
  test_get_field
  test_get_status
  test_get_verdict
  test_get_list
  test_extract_verdict_fallback
  test_parse_response

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
