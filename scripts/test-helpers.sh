#!/usr/bin/env bash
# test-helpers.sh - Unit tests for codex-helpers.sh
#
# Usage:
#   ./scripts/test-helpers.sh           # Run all tests

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
# Test: codex_strip_ansi
# ==============================================================================
test_strip_ansi() {
  echo ""
  echo "=== Testing: codex_strip_ansi ==="

  # Test 1: Strip color codes
  local input1=$'\033[31mred text\033[0m'
  local result1
  result1=$(codex_strip_ansi "$input1")
  if [ "$result1" = "red text" ]; then
    pass "strip_ansi: removes color codes"
  else
    fail "strip_ansi color" "Expected 'red text', got '$result1'"
  fi

  # Test 2: Strip cursor movement codes
  local input2=$'\033[32;3Hsome text'
  local result2
  result2=$(codex_strip_ansi "$input2")
  if [ "$result2" = "some text" ]; then
    pass "strip_ansi: removes cursor movement"
  else
    fail "strip_ansi cursor" "Expected 'some text', got '$result2'"
  fi

  # Test 3: No ANSI codes (passthrough)
  local input3="plain text"
  local result3
  result3=$(codex_strip_ansi "$input3")
  if [ "$result3" = "plain text" ]; then
    pass "strip_ansi: passes through plain text"
  else
    fail "strip_ansi plain" "Expected 'plain text', got '$result3'"
  fi

  # Test 4: Stdin mode
  local result4
  result4=$(echo -e '\033[1;32mbold green\033[0m' | codex_strip_ansi)
  if [ "$result4" = "bold green" ]; then
    pass "strip_ansi: works with stdin"
  else
    fail "strip_ansi stdin" "Expected 'bold green', got '$result4'"
  fi

  # Test 5: Empty input
  local result5
  result5=$(codex_strip_ansi "")
  if [ -z "$result5" ]; then
    pass "strip_ansi: handles empty input"
  else
    fail "strip_ansi empty" "Expected empty, got '$result5'"
  fi
}

# ==============================================================================
# Test: codex_write_prompt
# ==============================================================================
test_write_prompt() {
  echo ""
  echo "=== Testing: codex_write_prompt ==="

  # Save original tmp dir
  local orig_tmp_dir="${CODEX_TMP_DIR:-}"
  local test_tmp=".test-tmp-write-prompt-$$"
  CODEX_TMP_DIR="$test_tmp"
  rm -rf "$test_tmp"

  # Test 1: Write prompt content
  local prompt_content="This is a test prompt for Codex."
  local result
  result=$(codex_write_prompt "$prompt_content" "test")

  if [ -f "$result" ]; then
    pass "write_prompt: creates file"
  else
    fail "write_prompt create" "File not created: $result"
    rm -rf "$test_tmp"
    CODEX_TMP_DIR="$orig_tmp_dir"
    return
  fi

  # Test 2: File content matches
  local content
  content=$(cat "$result")
  if [ "$content" = "$prompt_content" ]; then
    pass "write_prompt: content matches"
  else
    fail "write_prompt content" "Content mismatch"
  fi

  # Test 3: File path includes prefix
  if [[ "$result" == *"/codex-test-"* ]]; then
    pass "write_prompt: path includes prefix"
  else
    fail "write_prompt prefix" "Expected prefix 'codex-test-' in path: $result"
  fi

  # Cleanup
  rm -rf "$test_tmp"
  CODEX_TMP_DIR="$orig_tmp_dir"
}

# ==============================================================================
# Test: codex_build_exec_command
# ==============================================================================
test_build_exec_command() {
  echo ""
  echo "=== Testing: codex_build_exec_command ==="

  # Test 1: Basic command with defaults
  local cmd1
  cmd1=$(codex_build_exec_command "/tmp/prompt.txt")
  if [ "$cmd1" = 'codex exec -s "read-only" - < "/tmp/prompt.txt"' ]; then
    pass "build_exec_command: basic command"
  else
    fail "build_exec_command basic" "Got: '$cmd1'"
  fi

  # Test 2: With custom sandbox
  local cmd2
  cmd2=$(codex_build_exec_command "/tmp/prompt.txt" "workspace-write")
  if [ "$cmd2" = 'codex exec -s "workspace-write" - < "/tmp/prompt.txt"' ]; then
    pass "build_exec_command: custom sandbox"
  else
    fail "build_exec_command sandbox" "Got: '$cmd2'"
  fi

  # Test 3: With model
  local cmd3
  cmd3=$(codex_build_exec_command "/tmp/prompt.txt" "read-only" "o4-mini")
  if [ "$cmd3" = 'codex exec -s "read-only" -m "o4-mini" - < "/tmp/prompt.txt"' ]; then
    pass "build_exec_command: with model"
  else
    fail "build_exec_command model" "Got: '$cmd3'"
  fi

  # Test 4: Empty model (should not add -m flag)
  local cmd4
  cmd4=$(codex_build_exec_command "/tmp/prompt.txt" "read-only" "")
  if [[ "$cmd4" != *"-m"* ]]; then
    pass "build_exec_command: no model flag when empty"
  else
    fail "build_exec_command empty model" "Should not contain -m flag: '$cmd4'"
  fi
}

# ==============================================================================
# Main
# ==============================================================================
main() {
  echo "codex-helpers.sh Test Suite"
  echo "============================"
  echo ""

  # Run tests (no external dependencies required)
  test_source_helpers
  test_hash_content
  test_generate_signal
  test_multiple_source
  test_tmp_directory

  # Lightweight metadata extraction tests
  test_extract_metadata
  test_get_field
  test_get_status
  test_get_verdict

  # Language directive tests
  test_get_language_directive

  # New function tests
  test_strip_ansi
  test_write_prompt
  test_build_exec_command

  # Summary
  echo ""
  echo "============================"
  echo "Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}, ${YELLOW}$SKIP skipped${NC}"
  echo ""

  # Exit with failure if any tests failed
  [ "$FAIL" -eq 0 ]
}

main "$@"
