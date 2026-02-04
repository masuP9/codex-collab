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
# Test: codex_send_prompt_file marker parsing
# ==============================================================================
test_send_prompt_file_marker_parsing() {
  echo ""
  echo "=== Testing: codex_send_prompt_file marker parsing ==="

  # Test the marker detection pattern used in codex_send_prompt_file
  # Pattern: [[ "$arg" == "<<"* ]] || [[ "$arg" == "RESPONSE_END_"* ]]

  # Test helper: mimics the exact pattern used in codex_send_prompt_file
  _is_end_marker() {
    local arg="$1"
    if [[ "$arg" == "<<"* ]] || [[ "$arg" == "RESPONSE_END_"* ]]; then
      return 0
    fi
    return 1
  }

  # Test 1: <<RESPONSE_END_xxx>> format (original format)
  if _is_end_marker "<<RESPONSE_END_123>>"; then
    pass "marker parsing: <<RESPONSE_END_xxx>> recognized"
  else
    fail "marker parsing" "<<RESPONSE_END_xxx>> not recognized as marker"
  fi

  # Test 2: RESPONSE_END_xxx format (without << >>)
  # This is the bug fix - should now be recognized
  if _is_end_marker "RESPONSE_END_123-456"; then
    pass "marker parsing: RESPONSE_END_xxx recognized"
  else
    fail "marker parsing" "RESPONSE_END_xxx not recognized as marker"
  fi

  # Test 3: Regular filename should NOT be detected as marker
  if _is_end_marker "src/file.ts"; then
    fail "marker parsing" "Regular filename incorrectly detected as marker"
  else
    pass "marker parsing: regular filename not detected as marker"
  fi

  # Test 4: NOT_RESPONSE_END_xxx should NOT be detected as marker
  # (doesn't start with "RESPONSE_END_")
  if _is_end_marker "NOT_RESPONSE_END_123"; then
    fail "marker parsing" "NOT_RESPONSE_END_xxx incorrectly detected as marker"
  else
    pass "marker parsing: NOT_RESPONSE_END_xxx not detected as marker"
  fi

  # Test 5: Empty string should NOT be marker
  if _is_end_marker ""; then
    fail "marker parsing" "Empty string incorrectly detected as marker"
  else
    pass "marker parsing: empty string not detected as marker"
  fi

  # Test 6: <<any_other>> format (starts with <<)
  if _is_end_marker "<<CUSTOM_MARKER>>"; then
    pass "marker parsing: <<CUSTOM_MARKER>> recognized"
  else
    fail "marker parsing" "<<CUSTOM_MARKER>> not recognized as marker"
  fi
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

  # Use relative path for test - function should return absolute path
  local test_tmp=".test-tmp-$$"
  local expected_abs_path="$(pwd)/$test_tmp"
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

  # Test codex_ensure_tmp_dir returns absolute path
  # Note: codex_ensure_tmp_dir was updated to return absolute paths for consistency
  if [ "$result" = "$expected_abs_path" ]; then
    pass "ensure_tmp_dir returns absolute path"
  else
    fail "ensure_tmp_dir return" "Expected '$expected_abs_path', got '$result'"
  fi

  # Test codex_tmp_path returns correct absolute path
  local path_result
  path_result=$(codex_tmp_path "test-file.txt")
  if [ "$path_result" = "$expected_abs_path/test-file.txt" ]; then
    pass "tmp_path returns absolute path"
  else
    fail "tmp_path" "Expected '$expected_abs_path/test-file.txt', got '$path_result'"
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

  # Save original values
  local orig_socket="${CODEX_TMUX_SOCKET:-}"
  local orig_tmux="${TMUX:-}"

  # Test without socket (clear both CODEX_TMUX_SOCKET and TMUX to prevent socket resolution)
  CODEX_TMUX_SOCKET=""
  TMUX=""
  local result
  result=$(codex_tmux_cmd)
  if [ "$result" = "tmux" ]; then
    pass "tmux_cmd without socket"
  else
    fail "tmux_cmd without socket" "Expected 'tmux', got '$result'"
  fi

  # Test with explicit socket (CODEX_TMUX_SOCKET takes priority)
  CODEX_TMUX_SOCKET="./test.sock"
  result=$(codex_tmux_cmd)
  if [ "$result" = "tmux -S ./test.sock" ]; then
    pass "tmux_cmd with socket"
  else
    fail "tmux_cmd with socket" "Expected 'tmux -S ./test.sock', got '$result'"
  fi

  # Restore original values
  CODEX_TMUX_SOCKET="$orig_socket"
  if [ -n "$orig_tmux" ]; then
    TMUX="$orig_tmux"
  else
    unset TMUX
  fi
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
# Test: codex_get_language_directive
# ==============================================================================
test_get_language_directive() {
  echo ""
  echo "=== Testing: codex_get_language_directive ==="

  # Test 1: English returns empty
  local result
  result=$(codex_get_language_directive "en")
  if [ -z "$result" ]; then
    pass "lang_directive: en returns empty"
  else
    fail "lang_directive en" "Expected empty, got '$result'"
  fi

  # Test 2: Japanese returns directive
  result=$(codex_get_language_directive "ja")
  if echo "$result" | grep -q "日本語で回答してください"; then
    pass "lang_directive: ja returns Japanese directive"
  else
    fail "lang_directive ja" "Expected Japanese directive, got '$result'"
  fi

  # Test 3: Empty string returns empty
  result=$(codex_get_language_directive "")
  if [ -z "$result" ]; then
    pass "lang_directive: empty returns empty"
  else
    fail "lang_directive empty" "Expected empty, got '$result'"
  fi

  # Test 4: Other language returns directive with that language
  result=$(codex_get_language_directive "fr")
  if echo "$result" | grep -q "frで回答してください"; then
    pass "lang_directive: other language returns directive"
  else
    fail "lang_directive fr" "Expected French directive, got '$result'"
  fi
}

# ==============================================================================
# Test: codex_acquire_lock / codex_release_lock
# ==============================================================================
test_lock_acquire_release() {
  echo ""
  echo "=== Testing: codex_acquire_lock / codex_release_lock ==="

  # Use a unique test directory
  local test_tmp
  test_tmp=$(mktemp -d)
  local original_tmp="${CODEX_TMP_DIR:-}"
  export CODEX_TMP_DIR="$test_tmp"

  # Test 1: First acquire should succeed
  if codex_acquire_lock "test-lock-$$" >/dev/null 2>&1; then
    pass "lock_acquire: first acquire succeeds"
  else
    fail "lock_acquire" "first acquire failed"
  fi

  # Test 2: Second acquire (same lock, same process) should succeed
  # Note: flock allows same process to re-acquire
  # So we test by checking lock file exists
  if [ -f "$test_tmp/test-lock-$$.lock" ]; then
    pass "lock_acquire: lock file created"
  else
    fail "lock_acquire" "lock file not created"
  fi

  # Test 3: Release should succeed
  if codex_release_lock >/dev/null 2>&1; then
    pass "lock_release: release succeeds"
  else
    fail "lock_release" "release failed"
  fi

  # Cleanup
  rm -rf "$test_tmp"
  if [ -n "$original_tmp" ]; then
    export CODEX_TMP_DIR="$original_tmp"
  else
    unset CODEX_TMP_DIR
  fi
}

# ==============================================================================
# Test: codex_resolve_tmux_socket
# ==============================================================================
test_resolve_tmux_socket() {
  echo ""
  echo "=== Testing: codex_resolve_tmux_socket ==="

  local original_tmux="${TMUX:-}"

  # Test 1: Absolute path should be returned as-is
  TMUX="/tmp/test-socket.sock,12345,0"
  local result
  result=$(codex_resolve_tmux_socket)
  if [ "$result" = "/tmp/test-socket.sock" ]; then
    pass "resolve_socket: absolute path returned as-is"
  else
    fail "resolve_socket absolute" "Expected '/tmp/test-socket.sock', got '$result'"
  fi

  # Test 2: Empty TMUX should return empty
  TMUX=""
  result=$(codex_resolve_tmux_socket)
  if [ -z "$result" ]; then
    pass "resolve_socket: empty TMUX returns empty"
  else
    fail "resolve_socket empty" "Expected empty, got '$result'"
  fi

  # Test 3: Relative path with non-existent socket should return error
  TMUX="./nonexistent.sock,12345,0"
  if ! codex_resolve_tmux_socket >/dev/null 2>&1; then
    pass "resolve_socket: nonexistent relative returns error"
  else
    fail "resolve_socket nonexistent" "Should return error for nonexistent socket"
  fi

  # Test 4: Relative path with existing socket (if python3 available)
  local test_base
  test_base=$(mktemp -d)
  mkdir -p "$test_base/child"

  if command -v python3 >/dev/null 2>&1; then
    # Create a real Unix socket using Python
    python3 -c "
import socket
import sys
sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.bind('$test_base/test.sock')
" 2>/dev/null

    if [ -S "$test_base/test.sock" ]; then
      # Run from child directory
      (
        cd "$test_base/child"
        TMUX="./test.sock,12345,0"
        result=$(codex_resolve_tmux_socket)
        if [ "$result" = "$test_base/test.sock" ]; then
          pass "resolve_socket: relative path resolved via parent search"
        else
          fail "resolve_socket relative" "Expected '$test_base/test.sock', got '$result'"
        fi
      )
    else
      skip "resolve_socket relative" "Could not create test socket"
    fi
    rm -f "$test_base/test.sock"
  else
    skip "resolve_socket relative" "python3 not available to create Unix socket"
  fi

  rm -rf "$test_base"

  # Restore original TMUX
  if [ -n "$original_tmux" ]; then
    TMUX="$original_tmux"
  else
    unset TMUX
  fi
}

# ==============================================================================
# Test: codex_send_chunked splitting logic
# ==============================================================================
test_send_chunked_splitting() {
  echo ""
  echo "=== Testing: codex_send_chunked splitting logic ==="

  # We can't easily test the actual sending without tmux,
  # but we can test the awk-based splitting logic separately

  # Test the awk splitting directly
  local text="ABCDEFGHIJKLMNO"
  local chunk_size=5
  local chunks

  # Use same awk logic as codex_send_chunked
  chunks=$(printf '%s' "$text" | awk -v size="$chunk_size" '
    BEGIN { ORS = "|" }
    {
      if (NR > 1) content = content "\n"
      content = content $0
    }
    END {
      len = length(content)
      if (len == 0) exit
      for (i = 1; i <= len; i += size) {
        print substr(content, i, size)
      }
    }
  ')

  # Expected: "ABCDE|FGHIJ|KLMNO|"
  if [ "$chunks" = "ABCDE|FGHIJ|KLMNO|" ]; then
    pass "send_chunked: splits evenly divisible text correctly"
  else
    fail "send_chunked even split" "Expected 'ABCDE|FGHIJ|KLMNO|', got '$chunks'"
  fi

  # Test with remainder
  text="ABCDEFGHIJKLMNOP"  # 16 chars
  chunks=$(printf '%s' "$text" | awk -v size="$chunk_size" '
    BEGIN { ORS = "|" }
    {
      if (NR > 1) content = content "\n"
      content = content $0
    }
    END {
      len = length(content)
      if (len == 0) exit
      for (i = 1; i <= len; i += size) {
        print substr(content, i, size)
      }
    }
  ')

  # Expected: "ABCDE|FGHIJ|KLMNO|P|"
  if [ "$chunks" = "ABCDE|FGHIJ|KLMNO|P|" ]; then
    pass "send_chunked: splits text with remainder correctly"
  else
    fail "send_chunked remainder" "Expected 'ABCDE|FGHIJ|KLMNO|P|', got '$chunks'"
  fi

  # Test with text shorter than chunk size
  text="ABC"
  chunks=$(printf '%s' "$text" | awk -v size="$chunk_size" '
    BEGIN { ORS = "|" }
    {
      if (NR > 1) content = content "\n"
      content = content $0
    }
    END {
      len = length(content)
      if (len == 0) exit
      for (i = 1; i <= len; i += size) {
        print substr(content, i, size)
      }
    }
  ')

  # Expected: "ABC|"
  if [ "$chunks" = "ABC|" ]; then
    pass "send_chunked: handles text shorter than chunk size"
  else
    fail "send_chunked short" "Expected 'ABC|', got '$chunks'"
  fi

  # Test with multiline text
  text=$'Line1\nLine2\nLine3'
  chunks=$(printf '%s' "$text" | awk -v size=10 '
    BEGIN { ORS = "|" }
    {
      if (NR > 1) content = content "\n"
      content = content $0
    }
    END {
      len = length(content)
      if (len == 0) exit
      for (i = 1; i <= len; i += size) {
        print substr(content, i, size)
      }
    }
  ')

  # "Line1\nLine2\nLine3" is 17 chars
  # Chunks of 10: "Line1\nLine" and "2\nLine3"
  local expected=$'Line1\nLine|2\nLine3|'
  if [ "$chunks" = "$expected" ]; then
    pass "send_chunked: preserves newlines in multiline text"
  else
    fail "send_chunked multiline" "Newlines not preserved correctly"
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

  # Language directive tests (no tmux required)
  test_get_language_directive

  # Lock mechanism tests (no tmux required)
  test_lock_acquire_release

  # Socket resolution tests (no tmux required, but may skip some cases)
  test_resolve_tmux_socket

  # Chunked sending logic tests (no tmux required - tests awk splitting only)
  test_send_chunked_splitting

  # Prompt function tests (no tmux required for marker parsing)
  test_send_prompt_file_marker_parsing

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
