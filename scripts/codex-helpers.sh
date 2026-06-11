#!/usr/bin/env bash
# codex-helpers.sh - Shared helper functions for codex-collab commands
#
# Usage:
#   # Source this file at the beginning of bash blocks in commands
#   HELPERS="${CLAUDE_PLUGIN_ROOT:-$(pwd)}/scripts/codex-helpers.sh"
#   if [ -f "$HELPERS" ]; then
#     source "$HELPERS"
#   fi

# Guard against multiple sourcing
if [ -n "${_CODEX_HELPERS_LOADED:-}" ]; then
  # shellcheck disable=SC2317 # exit 0 is intentional fallback: return succeeds when sourced, exit 0 when executed directly
  return 0 2>/dev/null || exit 0
fi
_CODEX_HELPERS_LOADED=1

# ==============================================================================
# Configuration
# ==============================================================================

# Default values (can be overridden before sourcing)
: "${CODEX_WAIT_TIMEOUT:=180}"      # seconds (max 600 for Bash tool)

# Temporary directory for all working files
: "${CODEX_TMP_DIR:=./tmp}"

# ==============================================================================
# Language Directive
# ==============================================================================

# Get language directive prefix for Codex prompts
# Usage: directive=$(codex_get_language_directive "ja")
# Returns: Language instruction string (empty if lang is "en" or not set)
#
# When language is set to a non-English value (e.g., "ja"), this function
# returns a directive to be prepended to Codex prompts. The directive includes:
# - Main response language instruction
# - Thinking/reasoning process language instruction
#
# Examples:
#   "ja" -> "**jaで回答してください。途中の説明や思考プロセスも日本語で記述してください。**"
#   "zh" -> "**zhで回答してください。途中の説明や思考プロセスもzhで記述してください。**"
#   "en" -> (empty, no directive needed)
codex_get_language_directive() {
  local lang="${1:-en}"

  # No directive needed for English (default)
  if [ "$lang" = "en" ] || [ -z "$lang" ]; then
    return 0
  fi

  # Return language-specific directive with thinking process instruction
  # For Japanese, use natural phrasing
  if [ "$lang" = "ja" ]; then
    echo "**日本語で回答してください。途中の説明や思考プロセスも日本語で記述してください。**"
  else
    echo "**${lang}で回答してください。途中の説明や思考プロセスも${lang}で記述してください。**"
  fi
  echo ""
}

# ==============================================================================
# Debug Logging
# ==============================================================================

# Debug logging (enabled with CODEX_DEBUG=1)
# Usage: codex_debug "message"
codex_debug() {
  if [ "${CODEX_DEBUG:-}" = "1" ]; then
    echo "[codex-debug] $*" >&2
  fi
}

# ==============================================================================
# Directory Setup
# ==============================================================================

# Ensure tmp directory exists and return absolute path
# Usage: codex_ensure_tmp_dir
# Returns: Absolute path to tmp directory (e.g., /full/path/to/project/tmp)
codex_ensure_tmp_dir() {
  local rel_dir="${CODEX_TMP_DIR:-tmp}"
  # Remove leading ./ if present
  rel_dir="${rel_dir#./}"
  # Create absolute path
  local tmp_dir
  tmp_dir="$(pwd)/${rel_dir}"
  if [ ! -d "$tmp_dir" ]; then
    mkdir -p "$tmp_dir"
  fi
  echo "$tmp_dir"
}

# Get path in tmp directory
# Usage: path=$(codex_tmp_path "filename.txt")
codex_tmp_path() {
  local filename="$1"
  local tmp_dir
  tmp_dir=$(codex_ensure_tmp_dir)
  echo "${tmp_dir}/${filename}"
}

# ==============================================================================
# Hash Functions
# ==============================================================================

# Cross-platform hash function (md5sum on Linux, md5 on macOS)
# Usage: echo "content" | codex_hash_content
codex_hash_content() {
  if command -v md5sum &>/dev/null; then
    md5sum | awk '{print $1}'
  else
    md5
  fi
}

# ==============================================================================
# Utility Functions
# ==============================================================================

# Generate unique signal/marker ID
# Usage: SIGNAL=$(codex_generate_signal "prefix")
codex_generate_signal() {
  local prefix="${1:-codex}"
  echo "${prefix}-$$-$(date +%s)-$RANDOM"
}

# ==============================================================================
# ANSI Escape Code Removal
# ==============================================================================

# Strip ANSI escape codes from text
# Usage: clean=$(codex_strip_ansi "$text")
#        cat file | codex_strip_ansi
# shellcheck disable=SC2120 # function intentionally works both with arg and via pipe (no-arg stdin mode)
codex_strip_ansi() {
  if [ $# -gt 0 ]; then
    printf '%s' "$1" | sed $'s/\033\\[[0-9;]*[a-zA-Z]//g; s/\033][^\007\033]*\007//g; s/\033][^\007\033]*\033\\\\//g'
  else
    sed $'s/\033\\[[0-9;]*[a-zA-Z]//g; s/\033][^\007\033]*\007//g; s/\033][^\007\033]*\033\\\\//g'
  fi
}

# ==============================================================================
# Prompt File Writing
# ==============================================================================

# Write prompt content to a temporary file
# Usage: prompt_file=$(codex_write_prompt "$content" "plan")
# Returns: Path to the created prompt file
codex_write_prompt() {
  local content="$1"
  local prefix="${2:-prompt}"
  local tmp_dir
  tmp_dir=$(codex_ensure_tmp_dir)
  local prompt_file="${tmp_dir}/codex-${prefix}-$$.txt"
  printf '%s' "$content" > "$prompt_file"
  echo "$prompt_file"
}

# ==============================================================================
# Codex Exec Command Building
# ==============================================================================

# Build codex exec command string
# Usage: cmd=$(codex_build_exec_command "prompt_file" "read-only" "o4-mini")
# Arguments:
#   prompt_file - Path to prompt file (will be piped via stdin)
#   sandbox     - Sandbox mode: read-only | workspace-write | danger-full-access (default: read-only)
#   model       - Model name (optional, uses codex default if empty)
# Returns: Command string ready for eval
codex_build_exec_command() {
  local prompt_file="$1"
  local sandbox="${2:-read-only}"
  local model="${3:-}"

  local cmd="codex exec"

  # Add sandbox option
  cmd="${cmd} -s \"${sandbox}\""

  # Add model option if specified
  if [ -n "$model" ]; then
    cmd="${cmd} -m \"${model}\""
  fi

  # Read from stdin via redirect (more reliable than pipe)
  cmd="${cmd} - < \"${prompt_file}\""

  echo "$cmd"
}

# ==============================================================================
# Codex Exec Runner
# ==============================================================================

# Run codex exec with full I/O handling
# Usage: codex_run_exec "prompt_file" "output_file" "read-only" "o4-mini"
# Arguments:
#   prompt_file - Path to prompt file
#   output_file - Path to save output (optional, defaults to tmp/codex-output-$$.md)
#   sandbox     - Sandbox mode (default: read-only)
#   model       - Model name (optional)
# Returns: Exit code from codex exec
# Side effects: Writes output to output_file, strips ANSI codes
codex_run_exec() {
  local prompt_file="$1"
  local output_file="${2:-$(codex_tmp_path "codex-output-$$.md")}"
  local sandbox="${3:-read-only}"
  local model="${4:-}"

  if [ ! -f "$prompt_file" ]; then
    echo "Error: prompt file not found: $prompt_file" >&2
    return 1
  fi

  # Check if codex is available
  if ! command -v codex &>/dev/null; then
    echo "Error: codex command not found" >&2
    return 1
  fi

  codex_debug "run_exec: prompt=$prompt_file output=$output_file sandbox=$sandbox model=$model"

  # Build command arguments
  local -a codex_args=(exec -s "$sandbox")
  if [ -n "$model" ]; then
    codex_args+=(-m "$model")
  fi
  codex_args+=(-)

  # Execute codex with stdin redirect and capture output
  # Use tee to save to file while also showing stdout
  # Strip ANSI escape codes from output
  # pipefail ensures codex's exit code propagates through the pipe
  local exit_code=0
  # shellcheck disable=SC2119 # codex_strip_ansi is used in pipe (stdin) mode here, not with $1
  (set -o pipefail; codex "${codex_args[@]}" < "$prompt_file" 2>&1 | codex_strip_ansi | tee "$output_file") || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    codex_debug "run_exec: codex exited with code $exit_code"
    echo "Warning: codex exec exited with code $exit_code" >&2
  fi

  codex_debug "run_exec: output saved to $output_file ($(wc -l < "$output_file") lines)"
  return "$exit_code"
}

# ==============================================================================
# Lightweight Metadata Extraction
# ==============================================================================

# Extract the metadata block from a response
# Usage: metadata=$(codex_extract_metadata "$response")
# Returns: The YAML content between --- markers (without the markers)
codex_extract_metadata() {
  local response="$1"

  # Extract the last --- ... --- block
  # Use awk to find and print the last complete block
  echo "$response" | awk '
    /^---$/ {
      if (in_block) {
        # End of block - save it
        last_block = block
        in_block = 0
        block = ""
      } else {
        # Start of block
        in_block = 1
        block = ""
      }
      next
    }
    in_block {
      if (block != "") {
        block = block "\n" $0
      } else {
        block = $0
      }
    }
    END {
      if (last_block != "") {
        print last_block
      }
    }
  '
}

# Get a simple field value from metadata
# Usage: value=$(codex_get_field "$metadata" "status")
codex_get_field() {
  local metadata="$1"
  local field="$2"

  echo "$metadata" | grep "^${field}:" | sed "s/^${field}: *//" | head -1 || true
}

# Get the status field (continue/stop)
# Usage: result=$(codex_get_status "$metadata")
# Returns: "continue" or "stop" (default: "stop")
codex_get_status() {
  local metadata="$1"
  local status_val
  status_val=$(codex_get_field "$metadata" "status")

  case "$status_val" in
    continue|stop)
      echo "$status_val"
      ;;
    *)
      echo "stop"  # Default to stop if not specified
      ;;
  esac
}

# Get the verdict field (pass/conditional/fail)
# Usage: verdict=$(codex_get_verdict "$metadata")
# Returns: "pass", "conditional", "fail", or empty
codex_get_verdict() {
  local metadata="$1"
  local verdict
  verdict=$(codex_get_field "$metadata" "verdict")

  case "$verdict" in
    pass|conditional|fail)
      echo "$verdict"
      ;;
    *)
      echo ""  # No verdict
      ;;
  esac
}

# ==============================================================================
# Codex Review Runner
# ==============================================================================

# Run codex review --uncommitted with full I/O handling
# Usage: codex_run_review "output_file" "model"
# Arguments:
#   output_file - Path to save output (optional, defaults to tmp/codex-review-output-$$.md)
#   model       - Model name (optional)
# Returns: Exit code (0=success, non-zero=fallback needed)
# Side effects: Writes output to output_file, strips ANSI codes
#
# Note: codex review --uncommitted does not accept a custom prompt as a
# positional argument. Custom review instructions should be provided via
# the fallback codex exec path instead.
codex_run_review() {
  local output_file="${1:-$(codex_tmp_path "codex-review-output-$$.md")}"
  local model="${2:-}"

  # Check if codex command exists
  if ! command -v codex &>/dev/null; then
    codex_debug "run_review: codex command not found"
    return 127
  fi

  # Check if codex review subcommand is available
  if ! codex review --help &>/dev/null 2>&1; then
    codex_debug "run_review: codex review subcommand not available"
    return 127
  fi

  codex_debug "run_review: output=$output_file model=$model"

  local -a review_args=(review --uncommitted)

  # Try with model config if specified
  if [ -n "$model" ]; then
    review_args+=(-c "model=\"${model}\"")
  fi

  local exit_code=0
  # shellcheck disable=SC2119 # codex_strip_ansi is used in pipe (stdin) mode here, not with $1
  (set -o pipefail; codex "${review_args[@]}" 2>&1 | codex_strip_ansi | tee "$output_file") || exit_code=$?

  # If model config caused failure, retry without it
  if [ "$exit_code" -ne 0 ] && [ -n "$model" ]; then
    codex_debug "run_review: retrying without model config (exit_code=$exit_code)"
    review_args=(review --uncommitted)
    exit_code=0
    # shellcheck disable=SC2119 # codex_strip_ansi is used in pipe (stdin) mode here, not with $1
    (set -o pipefail; codex "${review_args[@]}" 2>&1 | codex_strip_ansi | tee "$output_file") || exit_code=$?
  fi

  # Empty or very short output is also a failure
  if [ "$exit_code" -eq 0 ] && [ ! -s "$output_file" ]; then
    codex_debug "run_review: output file is empty"
    exit_code=1
  fi

  if [ "$exit_code" -ne 0 ]; then
    codex_debug "run_review: codex review exited with code $exit_code"
  else
    codex_debug "run_review: output saved to $output_file ($(wc -l < "$output_file") lines)"
  fi

  return "$exit_code"
}

# ==============================================================================
# Verdict Inference
# ==============================================================================

# Infer verdict from review response using multiple strategies
# Usage: verdict=$(codex_infer_verdict "$response")
# Returns: "pass", "conditional", "fail", or empty (unable to determine)
# Exit code: 0=verdict determined, 1=unable to determine
#
# Strategy order:
#   1. Metadata block (verdict: pass/conditional/fail)
#   2. [P1]-[P4] priority markers ([P1]/[P2] → fail, [P3]/[P4] → conditional)
#   3. Unable to determine → empty string, exit 1 (caller should retry/fallback)
#
# Note: We intentionally do NOT infer "pass" from the absence of markers.
# A response without markers may contain plain-text negative feedback that
# would be misclassified as pass. The caller should retry with a prompt
# requesting explicit verdict or treat as "conditional".
codex_infer_verdict() {
  local response="$1"

  # Strategy 1: metadata block
  local metadata verdict
  metadata=$(codex_extract_metadata "$response")
  if [ -n "$metadata" ]; then
    verdict=$(codex_get_verdict "$metadata")
    if [ -n "$verdict" ]; then
      echo "$verdict"
      return 0
    fi
  fi

  # Strategy 2: [P1]-[P4] priority markers
  local has_p1 has_p2 has_p3 has_p4
  has_p1=$(echo "$response" | grep -c '\[P1\]' || true)
  has_p2=$(echo "$response" | grep -c '\[P2\]' || true)
  has_p3=$(echo "$response" | grep -c '\[P3\]' || true)
  has_p4=$(echo "$response" | grep -c '\[P4\]' || true)

  if [ "$has_p1" -gt 0 ] || [ "$has_p2" -gt 0 ]; then
    echo "fail"
    return 0
  elif [ "$has_p3" -gt 0 ] || [ "$has_p4" -gt 0 ]; then
    echo "conditional"
    return 0
  fi

  # Unable to determine - caller should retry or treat as conditional
  echo ""
  return 1
}

# ==============================================================================
# Session State Management (for MCP/Bash dual-mode)
# ==============================================================================

# Sanitize task_id for safe use in filenames (allow only alphanumerics, hyphens, underscores)
# Usage: safe_id=$(codex_sanitize_task_id "$raw_id")
codex_sanitize_task_id() {
  printf '%s' "$1" | tr -cd 'a-zA-Z0-9_-' | head -c 128
}

# Escape a string for safe JSON embedding (handles quotes, backslashes, newlines)
# Usage: escaped=$(codex_json_escape "$value")
codex_json_escape() {
  printf '%s' "$1" \
    | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g' \
    | tr '\n' ' ' \
    | tr -d '\000-\010\013-\037'
}

# Save session state to a JSON file (task_id-scoped for concurrent isolation)
# Usage: codex_save_session_state "task_id" "mcp|bash" "thread_id" "read-only" "codex-leads"
# Arguments:
#   task_id   - Unique task identifier for isolation (sanitized for filename safety)
#   mode      - Communication mode: "mcp" or "bash"
#   thread_id - MCP thread ID (empty for bash mode). For claude-leads, use
#               codex_save_thread() to store named threads (threadB, threadC).
#   sandbox   - Sandbox mode
#   workflow  - Workflow type
# Side effects: Writes to tmp/codex-session-{task_id}.json
codex_save_session_state() {
  local task_id
  task_id=$(codex_sanitize_task_id "$1")
  local mode="$2"
  local thread_id="${3:-}"
  local sandbox="${4:-read-only}"
  local workflow="${5:-codex-leads}"

  if [ -z "$task_id" ]; then
    codex_debug "save_session_state: empty task_id after sanitization"
    return 1
  fi

  local tmp_dir
  tmp_dir=$(codex_ensure_tmp_dir)
  local state_file="${tmp_dir}/codex-session-${task_id}.json"

  local updated_at
  updated_at=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S%z)

  # Escape values for JSON safety
  local esc_thread_id esc_sandbox esc_workflow
  esc_thread_id=$(codex_json_escape "$thread_id")
  esc_sandbox=$(codex_json_escape "$sandbox")
  esc_workflow=$(codex_json_escape "$workflow")

  # Preserve existing threads block if state file already exists
  local existing_threads_block="{}"
  if [ -f "$state_file" ]; then
    local threads_content
    threads_content=$(sed -n '/"threads":/,/}/{ /"threads":/d; /}/d; p; }' "$state_file" | grep -v '^$' || true)
    if [ -n "$threads_content" ]; then
      existing_threads_block="{
${threads_content}
  }"
    fi
  fi

  cat > "$state_file" << EOJSON
{
  "mode": "${mode}",
  "threadId": "${esc_thread_id}",
  "threads": ${existing_threads_block},
  "sandbox": "${esc_sandbox}",
  "workflow": "${esc_workflow}",
  "taskId": "${task_id}",
  "updatedAt": "${updated_at}"
}
EOJSON

  codex_debug "save_session_state: saved to $state_file (mode=$mode, threadId=$thread_id)"
  echo "$state_file"
}

# Save a named thread to session state (for multi-thread topology, e.g., claude-leads Thread B/C)
# Usage: codex_save_thread "task_id" "threadB" "thread-id-value"
codex_save_thread() {
  local task_id
  task_id=$(codex_sanitize_task_id "$1")
  local thread_name="$2"
  local thread_value="$3"

  if [ -z "$task_id" ]; then
    codex_debug "save_thread: empty task_id after sanitization"
    return 1
  fi

  local tmp_dir
  tmp_dir=$(codex_ensure_tmp_dir)
  local state_file="${tmp_dir}/codex-session-${task_id}.json"

  if [ ! -f "$state_file" ]; then
    codex_debug "save_thread: state file not found: $state_file"
    return 1
  fi

  # Read current threads block, add/update the named thread
  local esc_value
  esc_value=$(codex_json_escape "$thread_value")
  local esc_name
  esc_name=$(codex_json_escape "$thread_name")

  # Simple approach: read file, replace threads block
  # Extract existing threads content (between "threads": { and })
  local existing_threads
  existing_threads=$(sed -n '/"threads":/,/}/{ /"threads":/d; /}/d; p; }' "$state_file" | grep -v '^$' || true)

  # Build new threads block
  local new_threads=""
  if [ -n "$existing_threads" ]; then
    # Remove existing entry for this thread name if present, and trailing comma
    local filtered
    filtered=$(echo "$existing_threads" | grep -vF "\"${esc_name}\":" || true)
    if [ -n "$filtered" ]; then
      # Ensure trailing comma on existing entries
      new_threads=$(echo "$filtered" | sed 's/[[:space:]]*$//' | sed '$ s/,*$/,/')
      new_threads="${new_threads}
    \"${esc_name}\": \"${esc_value}\""
    else
      new_threads="    \"${esc_name}\": \"${esc_value}\""
    fi
  else
    new_threads="    \"${esc_name}\": \"${esc_value}\""
  fi

  # Rebuild file with updated threads
  local updated_at
  updated_at=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S%z)

  local mode sandbox workflow threadId
  mode=$(grep '"mode"' "$state_file" | sed -E 's/.*: *"((\\.|[^"\\])*)".*/\1/' | head -1 || true)
  threadId=$(grep '"threadId"' "$state_file" | sed -E 's/.*: *"((\\.|[^"\\])*)".*/\1/' | head -1 || true)
  sandbox=$(grep '"sandbox"' "$state_file" | sed -E 's/.*: *"((\\.|[^"\\])*)".*/\1/' | head -1 || true)
  workflow=$(grep '"workflow"' "$state_file" | sed -E 's/.*: *"((\\.|[^"\\])*)".*/\1/' | head -1 || true)

  cat > "$state_file" << EOJSON
{
  "mode": "${mode}",
  "threadId": "${threadId}",
  "threads": {
${new_threads}
  },
  "sandbox": "${sandbox}",
  "workflow": "${workflow}",
  "taskId": "${task_id}",
  "updatedAt": "${updated_at}"
}
EOJSON

  codex_debug "save_thread: saved ${thread_name}=${thread_value} to $state_file"
}

# Load a named thread from session state
# Usage: thread_id=$(codex_load_thread "task_id" "threadB")
codex_load_thread() {
  local task_id
  task_id=$(codex_sanitize_task_id "$1")
  local thread_name="$2"

  if [ -z "$task_id" ]; then
    return 1
  fi

  local tmp_dir
  tmp_dir=$(codex_ensure_tmp_dir)
  local state_file="${tmp_dir}/codex-session-${task_id}.json"

  if [ ! -f "$state_file" ]; then
    return 1
  fi

  local esc_name
  esc_name=$(codex_json_escape "$thread_name")

  grep -F "\"${esc_name}\":" "$state_file" | sed -E 's/.*: *"((\\.|[^"\\])*)".*/\1/' | head -1 || true
}

# Load session state from a JSON file
# Usage: codex_load_session_state "task_id"
# Returns: Prints JSON content to stdout
# Side effects: Sets global variables SESSION_MODE, SESSION_THREAD_ID, SESSION_SANDBOX, SESSION_WORKFLOW
codex_load_session_state() {
  local task_id
  task_id=$(codex_sanitize_task_id "$1")

  if [ -z "$task_id" ]; then
    codex_debug "load_session_state: empty task_id after sanitization"
    return 1
  fi

  local tmp_dir
  tmp_dir=$(codex_ensure_tmp_dir)
  local state_file="${tmp_dir}/codex-session-${task_id}.json"

  if [ ! -f "$state_file" ]; then
    codex_debug "load_session_state: file not found: $state_file"
    return 1
  fi

  # Parse JSON fields using grep/sed (no jq dependency)
  # Guards with || true to prevent set -e failures on malformed files
  SESSION_MODE=$(grep '"mode"' "$state_file" | sed -E 's/.*: *"((\\.|[^"\\])*)".*/\1/' | head -1 || true)
  SESSION_THREAD_ID=$(grep '"threadId"' "$state_file" | sed -E 's/.*: *"((\\.|[^"\\])*)".*/\1/' | head -1 || true)
  # shellcheck disable=SC2034 # SESSION_SANDBOX is exported for use by callers that source this file
  SESSION_SANDBOX=$(grep '"sandbox"' "$state_file" | sed -E 's/.*: *"((\\.|[^"\\])*)".*/\1/' | head -1 || true)
  # shellcheck disable=SC2034 # SESSION_WORKFLOW is exported for use by callers that source this file
  SESSION_WORKFLOW=$(grep '"workflow"' "$state_file" | sed -E 's/.*: *"((\\.|[^"\\])*)".*/\1/' | head -1 || true)

  # Validate minimum required fields
  if [ -z "$SESSION_MODE" ]; then
    codex_debug "load_session_state: missing 'mode' field in $state_file"
    return 1
  fi

  codex_debug "load_session_state: loaded from $state_file (mode=$SESSION_MODE, threadId=$SESSION_THREAD_ID)"
  cat "$state_file"
}

# ==============================================================================
# Diff Size Tiering
# ==============================================================================

# Determine diff tier based on line count
# Usage: tier=$(codex_diff_tier "$diff_content")
# Returns: "small" (<=500 lines), "medium" (501-2000), or "large" (>2000)
codex_diff_tier() {
  local diff_content="$1"

  local line_count
  if [ -z "$diff_content" ]; then
    line_count=0
  else
    line_count=$(printf '%s\n' "$diff_content" | wc -l)
  fi

  if [ "$line_count" -le 500 ]; then
    echo "small"
  elif [ "$line_count" -le 2000 ]; then
    echo "medium"
  else
    echo "large"
  fi
}

# ==============================================================================
# Review Findings Extraction
# ==============================================================================

# Extract review findings from response
# Usage: findings=$(codex_extract_review_findings "$response")
# Returns: Extracted findings text (from metadata findings: or [P1]-[P4] markers)
codex_extract_review_findings() {
  local response="$1"
  local findings=""

  # Strategy 1: metadata findings
  local metadata
  metadata=$(codex_extract_metadata "$response")
  if [ -n "$metadata" ]; then
    local meta_findings
    meta_findings=$(echo "$metadata" | awk '
      /^findings:/ { in_findings=1; next }
      in_findings && /^  - / { print substr($0, 5); next }
      in_findings && /^[^ ]/ { in_findings=0 }
    ')
    if [ -n "$meta_findings" ]; then
      findings="$meta_findings"
    fi
  fi

  # Strategy 2: [P1]-[P4] markers (append if metadata had no findings)
  if [ -z "$findings" ]; then
    local marker_findings
    marker_findings=$(echo "$response" | grep -E '\[P[1-4]\]' || true)
    if [ -n "$marker_findings" ]; then
      findings="$marker_findings"
    fi
  fi

  echo "$findings"
}
