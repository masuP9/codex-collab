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
  # shellcheck source=codex-helpers.sh
  source "$HELPERS"
  local first_load="$_CODEX_HELPERS_LOADED"
  # shellcheck source=codex-helpers.sh
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
  local expected_abs_path
  expected_abs_path="$(pwd)/$test_tmp"
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
# Test: codex_infer_verdict
# ==============================================================================
test_infer_verdict() {
  echo ""
  echo "=== Testing: codex_infer_verdict ==="

  # Test 1: metadata verdict pass
  local response1="Review looks good.

---
verdict: pass
---"
  local result1
  result1=$(codex_infer_verdict "$response1")
  if [ "$result1" = "pass" ]; then
    pass "infer_verdict: metadata pass"
  else
    fail "infer_verdict metadata pass" "Expected 'pass', got '$result1'"
  fi

  # Test 2: metadata verdict conditional
  local response2="Some issues found.

---
verdict: conditional
findings:
  - minor style issue
---"
  local result2
  result2=$(codex_infer_verdict "$response2")
  if [ "$result2" = "conditional" ]; then
    pass "infer_verdict: metadata conditional"
  else
    fail "infer_verdict metadata conditional" "Expected 'conditional', got '$result2'"
  fi

  # Test 3: metadata verdict fail
  local response3="Critical issues.

---
verdict: fail
---"
  local result3
  result3=$(codex_infer_verdict "$response3")
  if [ "$result3" = "fail" ]; then
    pass "infer_verdict: metadata fail"
  else
    fail "infer_verdict metadata fail" "Expected 'fail', got '$result3'"
  fi

  # Test 4: [P1] marker → fail
  local response4="Review:
[P1] Critical security vulnerability in auth module
[P3] Minor naming inconsistency"
  local result4
  result4=$(codex_infer_verdict "$response4")
  if [ "$result4" = "fail" ]; then
    pass "infer_verdict: [P1] → fail"
  else
    fail "infer_verdict P1" "Expected 'fail', got '$result4'"
  fi

  # Test 5: [P2] marker → fail
  local response5="Review:
[P2] Missing error handling in database layer"
  local result5
  result5=$(codex_infer_verdict "$response5")
  if [ "$result5" = "fail" ]; then
    pass "infer_verdict: [P2] → fail"
  else
    fail "infer_verdict P2" "Expected 'fail', got '$result5'"
  fi

  # Test 6: [P3] only → conditional
  local response6="Review:
[P3] Consider adding more test coverage"
  local result6
  result6=$(codex_infer_verdict "$response6")
  if [ "$result6" = "conditional" ]; then
    pass "infer_verdict: [P3] → conditional"
  else
    fail "infer_verdict P3" "Expected 'conditional', got '$result6'"
  fi

  # Test 7: [P4] only → conditional
  local response7="Review:
[P4] Minor style suggestion: use const instead of let"
  local result7
  result7=$(codex_infer_verdict "$response7")
  if [ "$result7" = "conditional" ]; then
    pass "infer_verdict: [P4] → conditional"
  else
    fail "infer_verdict P4" "Expected 'conditional', got '$result7'"
  fi

  # Test 8: No findings + sufficient output → empty (unable to determine)
  # We do NOT auto-infer pass from absence of markers, as the response
  # may contain plain-text negative feedback without [P1]-[P4] markers.
  local response8="The code looks clean and well-structured.
All changes align with the implementation plan.
Error handling is appropriate.
Security considerations are addressed.
Test coverage is adequate.
No issues found in this review."
  local result8
  result8=$(codex_infer_verdict "$response8") || true
  if [ -z "$result8" ]; then
    pass "infer_verdict: no markers → empty (unable to determine)"
  else
    fail "infer_verdict no markers" "Expected empty, got '$result8'"
  fi

  # Test 9: Short output + no findings → empty (unable to determine)
  local response9="OK"
  local result9
  result9=$(codex_infer_verdict "$response9") || true
  if [ -z "$result9" ]; then
    pass "infer_verdict: short output → empty"
  else
    fail "infer_verdict short" "Expected empty, got '$result9'"
  fi

  # Test 10: [P1] + [P3] mixed → fail (highest severity wins)
  local response10="Review:
[P1] SQL injection vulnerability
[P3] Consider using a constant for the magic number
[P4] Minor formatting"
  local result10
  result10=$(codex_infer_verdict "$response10")
  if [ "$result10" = "fail" ]; then
    pass "infer_verdict: [P1]+[P3] mixed → fail"
  else
    fail "infer_verdict mixed" "Expected 'fail', got '$result10'"
  fi
}

# ==============================================================================
# Test: codex_extract_review_findings
# ==============================================================================
test_extract_review_findings() {
  echo ""
  echo "=== Testing: codex_extract_review_findings ==="

  # Test 1: metadata findings
  local response1="Review text.

---
verdict: conditional
findings:
  - severity: high
  - missing error handling
---"
  local result1
  result1=$(codex_extract_review_findings "$response1")
  if echo "$result1" | grep -q "severity: high"; then
    pass "extract_findings: metadata findings"
  else
    fail "extract_findings metadata" "Expected findings, got '$result1'"
  fi

  # Test 2: [P1]-[P4] markers
  local response2="Review:
[P1] Critical bug in auth
[P3] Style issue"
  local result2
  result2=$(codex_extract_review_findings "$response2")
  if echo "$result2" | grep -q '\[P1\]' && echo "$result2" | grep -q '\[P3\]'; then
    pass "extract_findings: [P1]-[P4] markers"
  else
    fail "extract_findings markers" "Expected P1/P3 findings, got '$result2'"
  fi

  # Test 3: No findings
  local response3="Everything looks good. No issues found."
  local result3
  result3=$(codex_extract_review_findings "$response3")
  if [ -z "$result3" ]; then
    pass "extract_findings: no findings → empty"
  else
    fail "extract_findings empty" "Expected empty, got '$result3'"
  fi

  # Test 4: metadata has findings key but no items
  local response4="Clean review.

---
verdict: pass
---"
  local result4
  result4=$(codex_extract_review_findings "$response4")
  if [ -z "$result4" ]; then
    pass "extract_findings: no findings items → empty"
  else
    fail "extract_findings no items" "Expected empty, got '$result4'"
  fi
}

# ==============================================================================
# Test: codex_run_review (with mock codex)
# ==============================================================================
test_run_review() {
  echo ""
  echo "=== Testing: codex_run_review ==="

  # Save original PATH and tmp dir
  local orig_path="$PATH"
  local orig_tmp_dir="${CODEX_TMP_DIR:-}"
  local test_tmp=".test-tmp-review-$$"
  CODEX_TMP_DIR="$test_tmp"
  rm -rf "$test_tmp"
  mkdir -p "$test_tmp"

  local mock_dir="$test_tmp/mock-bin"
  mkdir -p "$mock_dir"

  # Test 1: codex not in PATH → return 127
  PATH="/usr/bin:/bin"  # exclude mock dir and any real codex
  local exit1=0
  local out1="$test_tmp/out1.md"
  codex_run_review "$out1" "" || exit1=$?
  if [ "$exit1" -eq 127 ]; then
    pass "run_review: codex not found → 127"
  else
    fail "run_review not found" "Expected exit 127, got $exit1"
  fi

  # Test 2: codex exists but review --help fails → return 127
  cat > "$mock_dir/codex" << 'MOCK'
#!/bin/bash
if [ "$1" = "review" ] && [ "$2" = "--help" ]; then
  exit 1
fi
echo "mock output"
MOCK
  chmod +x "$mock_dir/codex"
  PATH="$mock_dir:/usr/bin:/bin"

  local exit2=0
  local out2="$test_tmp/out2.md"
  codex_run_review "$out2" "" || exit2=$?
  if [ "$exit2" -eq 127 ]; then
    pass "run_review: review not supported → 127"
  else
    fail "run_review not supported" "Expected exit 127, got $exit2"
  fi

  # Test 3: codex review works normally
  cat > "$mock_dir/codex" << 'MOCK'
#!/bin/bash
if [ "$1" = "review" ] && [ "$2" = "--help" ]; then
  exit 0
fi
if [ "$1" = "review" ] && [ "$2" = "--uncommitted" ]; then
  echo "Review complete. No issues found."
  echo "---"
  echo "verdict: pass"
  echo "---"
  exit 0
fi
echo "unknown command"
exit 1
MOCK
  chmod +x "$mock_dir/codex"
  PATH="$mock_dir:/usr/bin:/bin"

  local exit3=0
  local out3="$test_tmp/out3.md"
  codex_run_review "$out3" "" || exit3=$?
  if [ "$exit3" -eq 0 ] && grep -q "verdict: pass" "$out3"; then
    pass "run_review: successful review"
  else
    fail "run_review success" "Expected exit 0 + verdict pass, got exit=$exit3"
  fi

  # Test 4: codex review fails with non-zero → returns that code
  cat > "$mock_dir/codex" << 'MOCK'
#!/bin/bash
if [ "$1" = "review" ] && [ "$2" = "--help" ]; then
  exit 0
fi
if [ "$1" = "review" ] && [ "$2" = "--uncommitted" ]; then
  echo "Error: API failure"
  exit 2
fi
exit 1
MOCK
  chmod +x "$mock_dir/codex"
  PATH="$mock_dir:/usr/bin:/bin"

  local exit4=0
  local out4="$test_tmp/out4.md"
  codex_run_review "$out4" "" || exit4=$?
  if [ "$exit4" -ne 0 ]; then
    pass "run_review: non-zero exit → fallback signal"
  else
    fail "run_review failure" "Expected non-zero exit, got $exit4"
  fi

  # Tests 5-7: sandbox_mode is passed via -c (codex review has no -s flag)
  # Mock records every invocation's args so we can assert on them.
  local args_log
  args_log="$(pwd)/$test_tmp/args.log"
  cat > "$mock_dir/codex" << 'MOCK'
#!/bin/bash
if [ "$1" = "review" ] && [ "$2" = "--help" ]; then
  exit 0
fi
echo "$*" >> "$MOCK_ARGS_LOG"
# Fail when a model config is present, to exercise the retry path
for arg in "$@"; do
  case "$arg" in
    model=*) echo "Error: unknown model"; exit 2 ;;
  esac
done
echo "Review complete. No issues found."
echo "---"
echo "verdict: pass"
echo "---"
exit 0
MOCK
  chmod +x "$mock_dir/codex"
  PATH="$mock_dir:/usr/bin:/bin"
  export MOCK_ARGS_LOG="$args_log"

  # Test 5: default sandbox is read-only
  : > "$args_log"
  local out5="$test_tmp/out5.md"
  codex_run_review "$out5" "" >/dev/null 2>&1 || true
  if grep -q 'sandbox_mode="read-only"' "$args_log"; then
    pass "run_review: defaults to sandbox_mode=read-only"
  else
    fail "run_review default sandbox" "Expected sandbox_mode=\"read-only\" in args, got: $(cat "$args_log")"
  fi

  # Test 6: explicit sandbox mode is honored
  : > "$args_log"
  local out6="$test_tmp/out6.md"
  codex_run_review "$out6" "" "workspace-write" >/dev/null 2>&1 || true
  if grep -q 'sandbox_mode="workspace-write"' "$args_log"; then
    pass "run_review: explicit sandbox mode is passed through"
  else
    fail "run_review explicit sandbox" "Expected sandbox_mode=\"workspace-write\" in args, got: $(cat "$args_log")"
  fi

  # Test 7: sandbox_mode survives the retry-without-model path
  : > "$args_log"
  local out7="$test_tmp/out7.md"
  codex_run_review "$out7" "some-model" >/dev/null 2>&1 || true
  local retry_line
  retry_line=$(tail -1 "$args_log")
  if [ "$(wc -l < "$args_log")" -eq 2 ] \
    && echo "$retry_line" | grep -q 'sandbox_mode="read-only"' \
    && ! echo "$retry_line" | grep -q 'model='; then
    pass "run_review: retry without model keeps sandbox_mode"
  else
    fail "run_review retry sandbox" "Expected retry without model but with sandbox_mode, got: $(cat "$args_log")"
  fi

  # Cleanup
  unset MOCK_ARGS_LOG
  PATH="$orig_path"
  rm -rf "$test_tmp"
  CODEX_TMP_DIR="$orig_tmp_dir"
}

# ==============================================================================
# Test: codex_save_session_state / codex_load_session_state
# ==============================================================================
test_save_load_session_state() {
  echo ""
  echo "=== Testing: codex_save_session_state / codex_load_session_state ==="

  # Save original tmp dir
  local orig_tmp_dir="${CODEX_TMP_DIR:-}"
  local test_tmp=".test-tmp-session-$$"
  CODEX_TMP_DIR="$test_tmp"
  rm -rf "$test_tmp"

  # Test 1: Save session state
  local state_file
  state_file=$(codex_save_session_state "test-task-1" "mcp" "thread-abc-123" "read-only" "codex-leads")

  if [ -f "$state_file" ]; then
    pass "save_session_state: creates file"
  else
    fail "save_session_state create" "File not created: $state_file"
    rm -rf "$test_tmp"
    CODEX_TMP_DIR="$orig_tmp_dir"
    return
  fi

  # Test 2: Load session state (call directly, not in subshell, so globals are set)
  SESSION_MODE="" SESSION_THREAD_ID="" SESSION_SANDBOX="" SESSION_WORKFLOW=""
  local load_exit=0
  codex_load_session_state "test-task-1" > /dev/null || load_exit=$?

  if [ "$load_exit" -eq 0 ]; then
    pass "load_session_state: loads successfully"
  else
    fail "load_session_state" "Expected exit 0, got $load_exit"
  fi

  # Test 3: Verify loaded values
  if [ "$SESSION_MODE" = "mcp" ]; then
    pass "load_session_state: mode=mcp"
  else
    fail "load_session_state mode" "Expected 'mcp', got '$SESSION_MODE'"
  fi

  if [ "$SESSION_THREAD_ID" = "thread-abc-123" ]; then
    pass "load_session_state: threadId=thread-abc-123"
  else
    fail "load_session_state threadId" "Expected 'thread-abc-123', got '$SESSION_THREAD_ID'"
  fi

  if [ "$SESSION_SANDBOX" = "read-only" ]; then
    pass "load_session_state: sandbox=read-only"
  else
    fail "load_session_state sandbox" "Expected 'read-only', got '$SESSION_SANDBOX'"
  fi

  if [ "$SESSION_WORKFLOW" = "codex-leads" ]; then
    pass "load_session_state: workflow=codex-leads"
  else
    fail "load_session_state workflow" "Expected 'codex-leads', got '$SESSION_WORKFLOW'"
  fi

  # Test 4: Load non-existent task → return 1
  local load_exit2=0
  codex_load_session_state "nonexistent-task" > /dev/null 2>&1 || load_exit2=$?
  if [ "$load_exit2" -ne 0 ]; then
    pass "load_session_state: non-existent → error"
  else
    fail "load_session_state nonexistent" "Expected non-zero exit, got $load_exit2"
  fi

  # Test 5: Save with empty thread_id (bash mode)
  codex_save_session_state "test-task-bash" "bash" "" "read-only" "codex-leads" > /dev/null
  SESSION_MODE="" SESSION_THREAD_ID="" SESSION_SANDBOX="" SESSION_WORKFLOW=""
  codex_load_session_state "test-task-bash" > /dev/null
  if [ "$SESSION_MODE" = "bash" ] && [ -z "$SESSION_THREAD_ID" ]; then
    pass "save/load_session_state: bash mode with empty threadId"
  else
    fail "session_state bash mode" "mode='$SESSION_MODE', threadId='$SESSION_THREAD_ID'"
  fi

  # Cleanup
  rm -rf "$test_tmp"
  CODEX_TMP_DIR="$orig_tmp_dir"
}

# ==============================================================================
# Test: codex_diff_tier
# ==============================================================================
test_diff_tier() {
  echo ""
  echo "=== Testing: codex_diff_tier ==="

  # Test 1: Empty diff → small
  local result1
  result1=$(codex_diff_tier "")
  if [ "$result1" = "small" ]; then
    pass "diff_tier: empty → small"
  else
    fail "diff_tier empty" "Expected 'small', got '$result1'"
  fi

  # Test 2: Small diff (10 lines) → small
  local small_diff=""
  for i in $(seq 1 10); do
    small_diff="${small_diff}line $i
"
  done
  local result2
  result2=$(codex_diff_tier "$small_diff")
  if [ "$result2" = "small" ]; then
    pass "diff_tier: 10 lines → small"
  else
    fail "diff_tier 10 lines" "Expected 'small', got '$result2'"
  fi

  # Test 3: Exactly 500 lines → small (use seq to generate)
  local exact500
  exact500=$(seq 1 500 | tr '\n' '\n')
  local result3
  result3=$(codex_diff_tier "$exact500")
  if [ "$result3" = "small" ]; then
    pass "diff_tier: 500 lines → small"
  else
    fail "diff_tier 500 lines" "Expected 'small', got '$result3'"
  fi

  # Test 4: 501 lines → medium
  local medium_diff
  medium_diff=$(seq 1 501 | tr '\n' '\n')
  local result4
  result4=$(codex_diff_tier "$medium_diff")
  if [ "$result4" = "medium" ]; then
    pass "diff_tier: 501 lines → medium"
  else
    fail "diff_tier 501 lines" "Expected 'medium', got '$result4'"
  fi

  # Test 5: 2000 lines → medium
  local exact2000
  exact2000=$(seq 1 2000 | tr '\n' '\n')
  local result5
  result5=$(codex_diff_tier "$exact2000")
  if [ "$result5" = "medium" ]; then
    pass "diff_tier: 2000 lines → medium"
  else
    fail "diff_tier 2000 lines" "Expected 'medium', got '$result5'"
  fi

  # Test 6: 2001 lines → large
  local large_diff
  large_diff=$(seq 1 2001 | tr '\n' '\n')
  local result6
  result6=$(codex_diff_tier "$large_diff")
  if [ "$result6" = "large" ]; then
    pass "diff_tier: 2001 lines → large"
  else
    fail "diff_tier 2001 lines" "Expected 'large', got '$result6'"
  fi
}

# ==============================================================================
# Test: Session state isolation (task_id scoping)
# ==============================================================================
test_session_state_isolation() {
  echo ""
  echo "=== Testing: Session state isolation ==="

  # Save original tmp dir
  local orig_tmp_dir="${CODEX_TMP_DIR:-}"
  local test_tmp=".test-tmp-isolation-$$"
  CODEX_TMP_DIR="$test_tmp"
  rm -rf "$test_tmp"

  # Save two different sessions
  codex_save_session_state "task-A" "mcp" "thread-A" "read-only" "codex-leads" > /dev/null
  codex_save_session_state "task-B" "bash" "" "workspace-write" "claude-leads" > /dev/null

  # Load task-A and verify
  SESSION_MODE="" SESSION_THREAD_ID="" SESSION_SANDBOX="" SESSION_WORKFLOW=""
  codex_load_session_state "task-A" > /dev/null
  local mode_a="$SESSION_MODE"
  local thread_a="$SESSION_THREAD_ID"

  # Load task-B and verify
  SESSION_MODE="" SESSION_THREAD_ID="" SESSION_SANDBOX="" SESSION_WORKFLOW=""
  codex_load_session_state "task-B" > /dev/null
  local mode_b="$SESSION_MODE"
  local thread_b="$SESSION_THREAD_ID"

  # Verify isolation
  if [ "$mode_a" = "mcp" ] && [ "$thread_a" = "thread-A" ]; then
    pass "session_isolation: task-A has correct state"
  else
    fail "session_isolation task-A" "mode='$mode_a', threadId='$thread_a'"
  fi

  if [ "$mode_b" = "bash" ] && [ -z "$thread_b" ]; then
    pass "session_isolation: task-B has correct state"
  else
    fail "session_isolation task-B" "mode='$mode_b', threadId='$thread_b'"
  fi

  # Verify files are separate
  local tmp_abs
  tmp_abs=$(codex_ensure_tmp_dir)
  if [ -f "${tmp_abs}/codex-session-task-A.json" ] && [ -f "${tmp_abs}/codex-session-task-B.json" ]; then
    pass "session_isolation: separate files per task_id"
  else
    fail "session_isolation files" "Expected separate files for task-A and task-B"
  fi

  # Cleanup
  rm -rf "$test_tmp"
  CODEX_TMP_DIR="$orig_tmp_dir"
}

# ==============================================================================
# Test: codex_sanitize_task_id / codex_json_escape
# ==============================================================================
test_sanitize_and_escape() {
  echo ""
  echo "=== Testing: codex_sanitize_task_id / codex_json_escape ==="

  # Test 1: Normal task_id passes through
  local result1
  result1=$(codex_sanitize_task_id "collab-12345-1234567890")
  if [ "$result1" = "collab-12345-1234567890" ]; then
    pass "sanitize_task_id: normal id passes through"
  else
    fail "sanitize_task_id normal" "Expected 'collab-12345-1234567890', got '$result1'"
  fi

  # Test 2: Path traversal characters stripped
  local result2
  result2=$(codex_sanitize_task_id "../../../etc/passwd")
  if [ "$result2" = "etcpasswd" ]; then
    pass "sanitize_task_id: path traversal stripped"
  else
    fail "sanitize_task_id traversal" "Expected 'etcpasswd', got '$result2'"
  fi

  # Test 3: Special characters stripped
  local result3
  result3=$(codex_sanitize_task_id 'task "with; spaces & quotes')
  if [ "$result3" = "taskwithspacesquotes" ]; then
    pass "sanitize_task_id: special chars stripped"
  else
    fail "sanitize_task_id special" "Expected 'taskwithspacesquotes', got '$result3'"
  fi

  # Test 4: JSON escape quotes
  local result4
  result4=$(codex_json_escape 'value "with" quotes')
  if [ "$result4" = 'value \"with\" quotes' ]; then
    pass "json_escape: quotes escaped"
  else
    fail "json_escape quotes" "Expected escaped quotes, got '$result4'"
  fi

  # Test 5: JSON escape backslashes
  local result5
  result5=$(codex_json_escape 'path\to\file')
  if [ "$result5" = 'path\\to\\file' ]; then
    pass "json_escape: backslashes escaped"
  else
    fail "json_escape backslash" "Expected escaped backslash, got '$result5'"
  fi
}

# ==============================================================================
# Test: Plan 004 hardening — json_escape control chars, quoted values,
#       thread name anchoring, OSC ANSI stripping
# ==============================================================================
test_plan004_hardening() {
  echo ""
  echo "=== Testing: Plan 004 hardening ==="

  local orig_tmp_dir="${CODEX_TMP_DIR:-}"
  local test_tmp=".test-tmp-plan004-$$"
  CODEX_TMP_DIR="$test_tmp"
  rm -rf "$test_tmp"

  # --- Case 1: json_escape must not leave a raw tab in the output ---
  local tab_result
  tab_result=$(codex_json_escape "$(printf 'a\tb')")
  if printf '%s' "$tab_result" | grep -q "$(printf '\t')"; then
    fail "json_escape tab" "Raw tab survived json_escape: '$tab_result'"
  else
    pass "json_escape: tab escaped (no raw tab)"
  fi

  # --- Case 2: json_escape must not leave a CR in the output ---
  local cr_result
  cr_result=$(codex_json_escape "$(printf 'a\rb')")
  if printf '%s' "$cr_result" | grep -q "$(printf '\r')"; then
    fail "json_escape CR" "Raw CR survived json_escape: '$cr_result'"
  else
    pass "json_escape: CR removed (no raw CR)"
  fi

  # --- Case 3: Save/load with a workflow value containing a double-quote ---
  #             The JSON must not be corrupted; SESSION_MODE must load correctly.
  local task3="plan004-quoted-$$"
  codex_save_session_state "$task3" "mcp" "thread-xyz" "read-only" 'work"flow' > /dev/null
  SESSION_MODE="" SESSION_THREAD_ID="" SESSION_SANDBOX="" SESSION_WORKFLOW=""
  local load_exit3=0
  codex_load_session_state "$task3" > /dev/null 2>&1 || load_exit3=$?
  if [ "$load_exit3" -eq 0 ] && [ "$SESSION_MODE" = "mcp" ]; then
    pass "save/load: quoted workflow value — SESSION_MODE correct"
  else
    fail "save/load quoted workflow" "Expected exit 0 mode=mcp, got exit=$load_exit3 mode='$SESSION_MODE'"
  fi

  # --- Case 4: save_thread with a quoted thread value must not break the state file ---
  local task4="plan004-thread-quote-$$"
  codex_save_session_state "$task4" "mcp" "t-abc" "read-only" "claude-leads" > /dev/null
  codex_save_thread "$task4" "threadB" 'value"with"quotes' > /dev/null || true
  SESSION_MODE="" SESSION_THREAD_ID="" SESSION_SANDBOX="" SESSION_WORKFLOW=""
  local load_exit4=0
  codex_load_session_state "$task4" > /dev/null 2>&1 || load_exit4=$?
  if [ "$load_exit4" -eq 0 ] && [ "$SESSION_MODE" = "mcp" ]; then
    pass "save_thread: quoted value — state file stays valid"
  else
    fail "save_thread quoted value" "Expected exit 0 mode=mcp, got exit=$load_exit4 mode='$SESSION_MODE'"
  fi

  # --- Case 5: thread name anchoring — value containing another thread name must not collide ---
  # threadC's value deliberately contains the string "threadB"
  local task5="plan004-anchor-$$"
  codex_save_session_state "$task5" "mcp" "t-main" "read-only" "claude-leads" > /dev/null
  codex_save_thread "$task5" "threadB" "thread-B-123" > /dev/null || true
  codex_save_thread "$task5" "threadC" "contains-threadB-value" > /dev/null || true

  local loaded_c5 loaded_b5
  loaded_c5=$(codex_load_thread "$task5" "threadC")
  loaded_b5=$(codex_load_thread "$task5" "threadB")

  if [ "$loaded_c5" = "contains-threadB-value" ] && [ "$loaded_b5" = "thread-B-123" ]; then
    pass "thread anchor: threadC value containing 'threadB' does not collide"
  else
    fail "thread anchor" "threadB='$loaded_b5' threadC='$loaded_c5' (expected 'thread-B-123' and 'contains-threadB-value')"
  fi

  # Also check that updating threadB does not destroy threadC
  codex_save_thread "$task5" "threadB" "thread-B-updated" > /dev/null || true
  local loaded_b5u loaded_c5u
  loaded_b5u=$(codex_load_thread "$task5" "threadB")
  loaded_c5u=$(codex_load_thread "$task5" "threadC")
  if [ "$loaded_b5u" = "thread-B-updated" ] && [ "$loaded_c5u" = "contains-threadB-value" ]; then
    pass "thread anchor: updating threadB preserves threadC"
  else
    fail "thread anchor update" "threadB='$loaded_b5u' threadC='$loaded_c5u'"
  fi

  # Sub-case: value containing QUOTED "threadB" — the actual pre-fix bug shape.
  # Stored escaped as \"threadB\", which contains the substring "threadB" that the
  # old unanchored grep -v matched, dropping threadD when threadB was updated.
  codex_save_thread "$task5" "threadD" 'see "threadB" ref' > /dev/null || true
  codex_save_thread "$task5" "threadB" "thread-B-final" > /dev/null || true
  local loaded_d5 loaded_b5f
  loaded_d5=$(codex_load_thread "$task5" "threadD")
  loaded_b5f=$(codex_load_thread "$task5" "threadB")
  if [ "$loaded_d5" = 'see \"threadB\" ref' ] && [ "$loaded_b5f" = "thread-B-final" ]; then
    pass "thread anchor: quoted 'threadB' inside threadD value survives threadB update"
  else
    fail "thread anchor quoted-value" "threadD='$loaded_d5' threadB='$loaded_b5f' (expected escaped 'see \\\"threadB\\\" ref' and 'thread-B-final')"
  fi

  # Sub-case: value EXACTLY equal to another thread's name — the true pre-fix bug shape.
  # Old unanchored grep matched threadE's value delimiters (: "threadB"), so updating
  # threadB dropped threadE (data loss) and loading threadB could return threadE's line.
  codex_save_thread "$task5" "threadE" "threadB" > /dev/null || true
  codex_save_thread "$task5" "threadB" "thread-B-final2" > /dev/null || true
  local loaded_e5 loaded_b5x
  loaded_e5=$(codex_load_thread "$task5" "threadE")
  loaded_b5x=$(codex_load_thread "$task5" "threadB")
  if [ "$loaded_e5" = "threadB" ] && [ "$loaded_b5x" = "thread-B-final2" ]; then
    pass "thread anchor: value equal to another thread name survives update and loads correctly"
  else
    fail "thread anchor value-eq-name" "threadE='$loaded_e5' threadB='$loaded_b5x' (expected 'threadB' and 'thread-B-final2')"
  fi

  # --- Case 6: codex_strip_ansi must remove OSC sequences ---
  # OSC BEL-terminated: ESC ] 0 ; title BEL
  local osc_bel
  osc_bel=$(printf '\033]0;mytitle\007plain text')
  local result_bel
  result_bel=$(codex_strip_ansi "$osc_bel")
  if [ "$result_bel" = "plain text" ]; then
    pass "strip_ansi: removes OSC BEL-terminated sequence"
  else
    fail "strip_ansi OSC BEL" "Expected 'plain text', got '$result_bel'"
  fi

  # OSC ST-terminated: ESC ] 0 ; title ESC backslash
  local osc_st
  osc_st=$(printf '\033]0;mytitle\033\\plain text')
  local result_st
  result_st=$(codex_strip_ansi "$osc_st")
  if [ "$result_st" = "plain text" ]; then
    pass "strip_ansi: removes OSC ST-terminated sequence"
  else
    fail "strip_ansi OSC ST" "Expected 'plain text', got '$result_st'"
  fi

  # Cleanup
  rm -rf "$test_tmp"
  CODEX_TMP_DIR="$orig_tmp_dir"
}

# ==============================================================================
# Test: codex_save_thread / codex_load_thread (named threads)
# ==============================================================================
test_named_threads() {
  echo ""
  echo "=== Testing: codex_save_thread / codex_load_thread ==="

  # Save original tmp dir
  local orig_tmp_dir="${CODEX_TMP_DIR:-}"
  local test_tmp=".test-tmp-threads-$$"
  CODEX_TMP_DIR="$test_tmp"
  rm -rf "$test_tmp"

  # Create session state first
  codex_save_session_state "thread-test" "mcp" "thread-main" "read-only" "claude-leads" > /dev/null

  # Test 1: Save threadB
  local save_exit=0
  codex_save_thread "thread-test" "threadB" "thread-B-123" || save_exit=$?
  if [ "$save_exit" -eq 0 ]; then
    pass "save_thread: threadB saved"
  else
    fail "save_thread threadB" "Expected exit 0, got $save_exit"
  fi

  # Test 2: Load threadB
  local loaded_b
  loaded_b=$(codex_load_thread "thread-test" "threadB")
  if [ "$loaded_b" = "thread-B-123" ]; then
    pass "load_thread: threadB correct"
  else
    fail "load_thread threadB" "Expected 'thread-B-123', got '$loaded_b'"
  fi

  # Test 3: Save threadC (second thread)
  codex_save_thread "thread-test" "threadC" "thread-C-456" || true

  # Test 4: Both threads preserved
  local loaded_b2 loaded_c
  loaded_b2=$(codex_load_thread "thread-test" "threadB")
  loaded_c=$(codex_load_thread "thread-test" "threadC")
  if [ "$loaded_b2" = "thread-B-123" ] && [ "$loaded_c" = "thread-C-456" ]; then
    pass "save_thread: both threads preserved"
  else
    fail "save_thread both" "threadB='$loaded_b2', threadC='$loaded_c'"
  fi

  # Test 5: Update existing thread
  codex_save_thread "thread-test" "threadB" "thread-B-updated" || true
  local loaded_b3
  loaded_b3=$(codex_load_thread "thread-test" "threadB")
  if [ "$loaded_b3" = "thread-B-updated" ]; then
    pass "save_thread: update existing thread"
  else
    fail "save_thread update" "Expected 'thread-B-updated', got '$loaded_b3'"
  fi

  # Test 6: Load from non-existent task
  local loaded_none
  loaded_none=$(codex_load_thread "nonexistent-task" "threadB" 2>/dev/null || true)
  if [ -z "$loaded_none" ]; then
    pass "load_thread: non-existent task → empty"
  else
    fail "load_thread nonexistent" "Expected empty, got '$loaded_none'"
  fi

  # Test 7: Original session fields still intact after thread saves
  SESSION_MODE="" SESSION_THREAD_ID="" SESSION_SANDBOX="" SESSION_WORKFLOW=""
  codex_load_session_state "thread-test" > /dev/null
  if [ "$SESSION_MODE" = "mcp" ] && [ "$SESSION_THREAD_ID" = "thread-main" ]; then
    pass "save_thread: does not corrupt session fields"
  else
    fail "save_thread corruption" "mode='$SESSION_MODE', threadId='$SESSION_THREAD_ID'"
  fi

  # Test 8: Re-saving session state preserves named threads
  codex_save_session_state "thread-test" "mcp" "thread-main" "workspace-write" "claude-leads" > /dev/null
  local loaded_b_after loaded_c_after
  loaded_b_after=$(codex_load_thread "thread-test" "threadB")
  loaded_c_after=$(codex_load_thread "thread-test" "threadC")
  if [ "$loaded_b_after" = "thread-B-updated" ] && [ "$loaded_c_after" = "thread-C-456" ]; then
    pass "save_session_state: preserves named threads on re-save"
  else
    fail "session re-save threads" "threadB='$loaded_b_after', threadC='$loaded_c_after'"
  fi

  # Cleanup
  rm -rf "$test_tmp"
  CODEX_TMP_DIR="$orig_tmp_dir"
}

# ==============================================================================
# Test: Malformed state file recovery
# ==============================================================================
test_malformed_state_file() {
  echo ""
  echo "=== Testing: Malformed state file recovery ==="

  # Save original tmp dir
  local orig_tmp_dir="${CODEX_TMP_DIR:-}"
  local test_tmp=".test-tmp-malformed-$$"
  CODEX_TMP_DIR="$test_tmp"
  rm -rf "$test_tmp"
  mkdir -p "$test_tmp"

  # Test 1: Completely empty file
  echo -n "" > "$test_tmp/codex-session-empty-task.json"
  SESSION_MODE="" SESSION_THREAD_ID="" SESSION_SANDBOX="" SESSION_WORKFLOW=""
  local exit1=0
  codex_load_session_state "empty-task" > /dev/null 2>&1 || exit1=$?
  if [ "$exit1" -ne 0 ]; then
    pass "malformed: empty file → error (missing mode)"
  else
    fail "malformed empty" "Expected error for empty file, got success"
  fi

  # Test 2: Partial JSON (has mode but missing other fields)
  echo '{"mode": "mcp"}' > "$test_tmp/codex-session-partial-task.json"
  SESSION_MODE="" SESSION_THREAD_ID="" SESSION_SANDBOX="" SESSION_WORKFLOW=""
  local exit2=0
  codex_load_session_state "partial-task" > /dev/null 2>&1 || exit2=$?
  if [ "$exit2" -eq 0 ] && [ "$SESSION_MODE" = "mcp" ]; then
    pass "malformed: partial JSON → loads mode, tolerates missing fields"
  else
    fail "malformed partial" "Expected success with mode=mcp, got exit=$exit2 mode='$SESSION_MODE'"
  fi

  # Cleanup
  rm -rf "$test_tmp"
  CODEX_TMP_DIR="$orig_tmp_dir"
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

  # Verdict inference and review tests
  test_infer_verdict
  test_extract_review_findings
  test_run_review

  # Session state and diff tier tests
  test_save_load_session_state
  test_diff_tier
  test_session_state_isolation
  test_sanitize_and_escape
  test_plan004_hardening
  test_named_threads
  test_malformed_state_file

  # Summary
  echo ""
  echo "============================"
  echo "Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}, ${YELLOW}$SKIP skipped${NC}"
  echo ""

  # Exit with failure if any tests failed
  [ "$FAIL" -eq 0 ]
}

main "$@"
