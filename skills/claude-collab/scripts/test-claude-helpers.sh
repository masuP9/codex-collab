#!/usr/bin/env bash

set -e -u -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HELPERS="$SCRIPT_DIR/claude-helpers.sh"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

export CLAUDE_COLLAB_TMP_DIR="$TEST_DIR/tmp"
source "$HELPERS"

test "$CLAUDE_COLLAB_PROJECT_DIR" = "$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
test -d "$(claude_tmp_dir)"
test "$(claude_tmp_path output.md)" = "$TEST_DIR/tmp/output.md"

prompt_file="$(claude_write_prompt "review this" "test")"
test -f "$prompt_file"
test "$(cat "$prompt_file")" = "review this"

second_prompt_file="$(claude_write_prompt "review this too" "test")"
test "$second_prompt_file" != "$prompt_file"
test "$(cat "$second_prompt_file")" = "review this too"

fake_bin="$TEST_DIR/bin"
mkdir -p "$fake_bin"
cat > "$fake_bin/claude" <<'EOF'
#!/usr/bin/env bash
printf 'args:'
printf ' <%s>' "$@"
printf '\ncwd:%s' "$(pwd)"
printf '\ncaller:%s' "${CLAUDE_COLLAB_CALLER:-}"
printf '\nstdin:'
cat
EOF
chmod +x "$fake_bin/claude"

output_file="$(claude_tmp_path output.md)"
PATH="$fake_bin:$PATH" claude_run_print "$prompt_file" "$output_file" sonnet >/dev/null

grep -q '<-p>' "$output_file"
grep -q '<--disable-slash-commands>' "$output_file"
grep -q '<--permission-mode> <plan>' "$output_file"
grep -q '<--tools> <Read,Glob,Grep>' "$output_file"
grep -q '<--no-session-persistence>' "$output_file"
grep -q '<--model> <sonnet>' "$output_file"
grep -q 'stdin:review this' "$output_file"

# Regression: missing prompt and missing claude executable fail cleanly.
missing_prompt_stderr="$(claude_tmp_path missing-prompt-stderr.txt)"
missing_prompt_status=0
claude_run_print "$TEST_DIR/missing-prompt.md" >/dev/null 2>"$missing_prompt_stderr" || missing_prompt_status=$?
test "$missing_prompt_status" -eq 1
grep -q 'prompt file not found' "$missing_prompt_stderr"

missing_claude_stderr="$(claude_tmp_path missing-claude-stderr.txt)"
missing_claude_status=0
PATH="/usr/bin:/bin" claude_run_print "$prompt_file" >/dev/null 2>"$missing_claude_stderr" || missing_claude_status=$?
test "$missing_claude_status" -eq 1
grep -q 'claude command not found' "$missing_claude_stderr"

# Regression: claude_run_print must surface timeout (exit 124) with an error message.
# Requires the `timeout` command; without it the helper runs claude directly and can't time out.
if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then
  cat > "$fake_bin/claude" <<'EOF'
#!/usr/bin/env bash
sleep 10
EOF
  chmod +x "$fake_bin/claude"

  timeout_prompt="$(claude_write_prompt "slow request" "timeout")"
  timeout_output="$(claude_tmp_path timeout-output.md)"
  timeout_stderr="$(claude_tmp_path timeout-stderr.txt)"

  timeout_status=0
  (
    export PATH="$fake_bin:$PATH"
    export CLAUDE_COLLAB_TIMEOUT=1
    claude_run_print "$timeout_prompt" "$timeout_output"
  ) >/dev/null 2>"$timeout_stderr" || timeout_status=$?

  test "$timeout_status" -eq 124
  grep -q 'claude consultation timed out after 1 seconds' "$timeout_stderr"
else
  printf 'skipping claude_run_print timeout test: timeout command not available\n'
fi

cat > "$fake_bin/claude" <<'EOF'
#!/usr/bin/env bash
printf 'args:'
printf ' <%s>' "$@"
printf '\ncwd:%s' "$(pwd)"
printf '\ncaller:%s' "${CLAUDE_COLLAB_CALLER:-}"
printf '\nstdin:'
cat
EOF
chmod +x "$fake_bin/claude"

review_output="$(claude_tmp_path review-output.md)"
review_cwd="$TEST_DIR/review-cwd"
mkdir -p "$review_cwd"
CLAUDE_COLLAB_PROJECT_DIR="$review_cwd" PATH="$fake_bin:$PATH" claude_run_review "$prompt_file" "$review_output" sonnet >/dev/null

grep -q '<--disable-slash-commands>' "$review_output"
grep -q '<--permission-mode> <plan>' "$review_output"
grep -q '<--tools> <>' "$review_output"
grep -q '<--no-session-persistence>' "$review_output"
grep -q '<--effort> <low>' "$review_output"
grep -q '<--append-system-prompt> <You are a read-only code reviewer invoked by Codex. This is a leaf invocation.' "$review_output"
grep -q "cwd:$review_cwd" "$review_output"
grep -q 'caller:codex' "$review_output"

invalid_cwd_stderr="$(claude_tmp_path invalid-cwd-stderr.txt)"
invalid_cwd_status=0
CLAUDE_COLLAB_PROJECT_DIR="$TEST_DIR/missing-cwd" PATH="$fake_bin:$PATH" claude_run_review "$prompt_file" "$review_output" >/dev/null 2>"$invalid_cwd_stderr" || invalid_cwd_status=$?
test "$invalid_cwd_status" -eq 1
grep -q 'claude working directory not found' "$invalid_cwd_stderr"

# Regression: review timeout overrides the general consultation timeout.
if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then
  cat > "$fake_bin/claude" <<'EOF'
#!/usr/bin/env bash
sleep 10
EOF
  chmod +x "$fake_bin/claude"

  review_timeout_stderr="$(claude_tmp_path review-timeout-stderr.txt)"
  review_timeout_status=0
  (
    export PATH="$fake_bin:$PATH"
    export CLAUDE_COLLAB_TIMEOUT=9
    export CLAUDE_COLLAB_REVIEW_TIMEOUT=1
    claude_run_review "$prompt_file" "$review_output"
  ) >/dev/null 2>"$review_timeout_stderr" || review_timeout_status=$?

  test "$review_timeout_status" -eq 124
  grep -q 'claude consultation timed out after 1 seconds' "$review_timeout_stderr"
else
  printf 'skipping claude_run_review timeout test: timeout command not available\n'
fi

printf 'claude helper tests passed\n'
