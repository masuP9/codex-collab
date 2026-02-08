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
  [ "${CODEX_DEBUG:-}" = "1" ] && echo "[codex-debug] $*" >&2
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
  local tmp_dir="$(pwd)/${rel_dir}"
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
codex_strip_ansi() {
  if [ $# -gt 0 ]; then
    printf '%s' "$1" | sed $'s/\033\\[[0-9;]*[a-zA-Z]//g'
  else
    sed $'s/\033\\[[0-9;]*[a-zA-Z]//g'
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

  local cmd="cat \"${prompt_file}\" | codex exec"

  # Add sandbox option
  cmd="${cmd} -s \"${sandbox}\""

  # Add model option if specified
  if [ -n "$model" ]; then
    cmd="${cmd} -m \"${model}\""
  fi

  # Read from stdin (the - flag)
  cmd="${cmd} -"

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

  # Execute codex and capture output
  # Use tee to save to file while also showing stdout
  # Strip ANSI escape codes from output
  # pipefail ensures codex's exit code propagates through the pipe
  local exit_code=0
  (set -o pipefail; cat "$prompt_file" | codex "${codex_args[@]}" 2>&1 | codex_strip_ansi | tee "$output_file") || exit_code=$?

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
