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
: "${CODEX_WAIT_TIMEOUT:=180}"      # seconds
: "${CODEX_POLL_INTERVAL:=2}"       # seconds
: "${CODEX_IDLE_THRESHOLD:=5}"      # polls without change
: "${CODEX_CAPTURE_LINES:=5000}"    # lines to capture from pane
: "${CODEX_CHUNK_SIZE:=200}"        # chunk size for chunked sending (characters)
: "${CODEX_CHUNK_DELAY:=0.02}"      # delay between chunks (seconds)

# Temporary directory for all working files
: "${CODEX_TMP_DIR:=./tmp}"

# Project-local tmux socket (for bidirectional communication)
# When set, all tmux commands use this socket instead of default
: "${CODEX_TMUX_SOCKET:=}"          # e.g., "./collab.sock"

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
# Tmux Socket Helper
# ==============================================================================

# Resolve relative socket path from $TMUX environment variable to absolute path
# Usage: abs_socket=$(codex_resolve_tmux_socket)
# Returns: Absolute socket path if found, empty string otherwise
#
# When tmux is started with `tmux -S ./collab.sock`, the $TMUX variable contains
# a relative path like `./collab.sock,PID,INDEX`. If the current working directory
# changes (e.g., Claude Code runs in a subdirectory), tmux commands fail because
# they can't find the socket at the relative path.
#
# This function:
# 1. Extracts the socket path from $TMUX (first comma-separated field)
# 2. If it's a relative path, searches upward from cwd to find the socket file
# 3. Returns the absolute path if found
codex_resolve_tmux_socket() {
  local tmux_val="${TMUX:-}"

  # No TMUX variable set
  if [ -z "$tmux_val" ]; then
    return 0
  fi

  # Extract socket path (first field before comma)
  local socket_path
  socket_path=$(echo "$tmux_val" | cut -d',' -f1)

  # If already absolute, return as-is
  if [[ "$socket_path" == /* ]]; then
    echo "$socket_path"
    return 0
  fi

  # Handle relative paths (./foo.sock or foo.sock)
  # Strip leading ./ if present
  local socket_name="${socket_path#./}"

  # Search upward from current directory to find the socket file
  local search_dir
  search_dir=$(pwd)

  while [ "$search_dir" != "/" ]; do
    if [ -S "${search_dir}/${socket_name}" ]; then
      echo "${search_dir}/${socket_name}"
      return 0
    fi
    search_dir=$(dirname "$search_dir")
  done

  # Check root as last resort
  if [ -S "/${socket_name}" ]; then
    echo "/${socket_name}"
    return 0
  fi

  # Socket not found - return empty to trigger default tmux fallback
  # Returning the original relative path would cause the same failure
  codex_debug "resolve_tmux_socket: socket '$socket_name' not found in any parent directory"
  return 1
}

# Execute tmux command with proper socket handling
# Usage: codex_tmux list-panes -s
#        codex_tmux display-message -p '#{pane_id}'
#
# This is the preferred way to run tmux commands. It handles:
# 1. CODEX_TMUX_SOCKET (explicit override)
# 2. Relative socket paths in $TMUX (auto-resolved to absolute)
# 3. Default tmux socket
#
# Unlike codex_tmux_cmd() which returns a string, this function directly
# executes tmux, avoiding word-splitting issues in zsh.
codex_tmux() {
  # Explicit socket override takes priority
  if [ -n "${CODEX_TMUX_SOCKET:-}" ]; then
    tmux -S "$CODEX_TMUX_SOCKET" "$@"
    return $?
  fi

  # Try to resolve socket from $TMUX (handles relative paths)
  local resolved_socket
  resolved_socket=$(codex_resolve_tmux_socket)

  if [ -n "$resolved_socket" ]; then
    tmux -S "$resolved_socket" "$@"
    return $?
  fi

  # Default: use tmux without explicit socket
  tmux "$@"
}

# DEPRECATED: Get tmux command as a string
# Usage: cmd=$(codex_tmux_cmd)
#        eval "$cmd list-panes"  # Note: requires eval in zsh!
#
# WARNING: This function returns a string like "tmux -S /path/to/socket".
# In zsh, variable expansion does NOT split on spaces by default, so
# `$cmd list-panes` fails. Use codex_tmux() instead, which directly
# executes tmux and works in both bash and zsh.
#
# Kept for backward compatibility only.
codex_tmux_cmd() {
  # Explicit socket override takes priority
  if [ -n "${CODEX_TMUX_SOCKET:-}" ]; then
    echo "tmux -S $CODEX_TMUX_SOCKET"
    return 0
  fi

  # Try to resolve socket from $TMUX (handles relative paths)
  local resolved_socket
  resolved_socket=$(codex_resolve_tmux_socket)

  if [ -n "$resolved_socket" ]; then
    echo "tmux -S $resolved_socket"
    return 0
  fi

  # Default: use tmux without explicit socket
  echo "tmux"
}

# ==============================================================================
# Pane Detection Functions
# ==============================================================================

# Verify if a pane exists and is running Codex
# Usage: codex_verify_pane "$PANE_ID"
# Returns: 0 if valid Codex pane, 1 otherwise
# Outputs: "valid" or error message
codex_verify_pane() {
  local pane_id="$1"

  if [ -z "$pane_id" ]; then
    codex_debug "verify_pane: empty pane_id"
    echo "error:empty_pane_id"
    return 1
  fi

  # Validate pane ID format (should be %N where N is a number)
  if ! echo "$pane_id" | grep -qE '^%[0-9]+$'; then
    codex_debug "verify_pane: invalid pane_id format: $pane_id"
    echo "error:invalid_pane_id_format"
    return 1
  fi

  # Check if pane exists using direct query (more reliable than list-panes + grep)
  # display-message -t returns empty string for non-existent panes
  codex_debug "verify_pane: checking pane $pane_id"

  local queried_pane
  queried_pane=$(codex_tmux display-message -t "$pane_id" -p '#{pane_id}' 2>/dev/null)
  if [ -z "$queried_pane" ] || [ "$queried_pane" != "$pane_id" ]; then
    codex_debug "verify_pane: pane $pane_id not found (queried: '$queried_pane')"
    echo "error:pane_not_found"
    return 1
  fi

  # CRITICAL: Verify pane belongs to current session
  # display-message -t can access panes from ANY session, so we must explicitly check
  local current_session pane_session
  current_session=$(codex_tmux display-message -p '#{session_id}' 2>/dev/null)
  pane_session=$(codex_tmux display-message -t "$pane_id" -p '#{session_id}' 2>/dev/null)
  if [ "$pane_session" != "$current_session" ]; then
    codex_debug "verify_pane: pane $pane_id belongs to different session (pane: $pane_session, current: $current_session)"
    echo "error:wrong_session"
    return 1
  fi

  # Check if pane is running Codex
  local pane_cmd
  pane_cmd=$(codex_tmux display-message -t "$pane_id" -p '#{pane_current_command}' 2>/dev/null)
  codex_debug "verify_pane: pane $pane_id running: $pane_cmd"

  # Priority 1: Native codex command (most reliable)
  if [ "$pane_cmd" = "codex" ]; then
    codex_debug "verify_pane: pane $pane_id is valid (codex command)"
    echo "valid"
    return 0
  fi

  # Priority 2: Node process with Codex patterns (legacy/npm run)
  if [ "$pane_cmd" = "node" ]; then
    codex_debug "verify_pane: pane $pane_id running node, checking content patterns"
    # Use larger scrollback (-S -2000) to find Codex banner even if scrolled
    local pane_content
    pane_content=$(codex_tmux capture-pane -t "$pane_id" -p -S -2000 2>/dev/null)

    # Primary: Codex banner (may scroll out of view)
    if echo "$pane_content" | grep -q "│ >_ OpenAI Codex"; then
      codex_debug "verify_pane: pane $pane_id is valid (Codex banner found)"
      echo "valid"
      return 0
    fi
    # Secondary: Codex prompt character or typical output
    if echo "$pane_content" | grep -qE "^› |Worked for [0-9]+|You approved codex"; then
      codex_debug "verify_pane: pane $pane_id is valid (Codex prompt/output pattern)"
      echo "valid"
      return 0
    fi
    codex_debug "verify_pane: pane $pane_id is node but no Codex patterns found"
  fi

  codex_debug "verify_pane: pane $pane_id is not a Codex pane"
  echo "error:not_codex_pane"
  return 1
}

# Find Codex pane using stored ID or auto-detection
# Usage: PANE=$(codex_find_pane [pane_id_file])
# Returns: Pane ID or empty string
# Outputs: Detection messages to stderr
codex_find_pane() {
  local pane_id_file="${1:-$(codex_tmp_path codex-pane-id)}"
  local found_pane=""

  codex_debug "find_pane: starting pane detection"

  # Method 1: Check stored pane ID
  if [ -f "$pane_id_file" ]; then
    local stored_pane
    stored_pane=$(cat "$pane_id_file")
    codex_debug "find_pane: checking stored pane ID: $stored_pane"

    local verify_result
    verify_result=$(codex_verify_pane "$stored_pane")

    if [ "$verify_result" = "valid" ]; then
      echo "$stored_pane"
      echo "Found Codex pane from stored ID: $stored_pane" >&2
      return 0
    else
      codex_debug "find_pane: stored pane invalid: $verify_result"
      echo "Stored pane $stored_pane is invalid ($verify_result), scanning for Codex panes..." >&2
    fi
  else
    codex_debug "find_pane: no stored pane ID file at $pane_id_file"
    echo "No stored pane ID, scanning for Codex panes..." >&2
  fi

  # Method 2: Auto-detect Codex pane (within current session only)
  local pane_list
  pane_list=$(codex_tmux list-panes -s -F '#{pane_id}' 2>&1)
  if [ $? -ne 0 ]; then
    codex_debug "find_pane: failed to list panes: $pane_list"
    echo "Warning: Failed to list tmux panes" >&2
    echo "Error: $pane_list" >&2
    return 1
  fi
  codex_debug "find_pane: scanning panes: $(echo "$pane_list" | tr '\n' ' ')"

  # Search all panes for Codex (use while read for reliable line parsing)
  local codex_panes=""
  while IFS= read -r pane; do
    [ -z "$pane" ] && continue
    local pane_cmd
    pane_cmd=$(codex_tmux display-message -t "$pane" -p '#{pane_current_command}' 2>/dev/null)
    codex_debug "find_pane: pane $pane running: $pane_cmd"

    # Priority 1: Native codex command (most reliable)
    if [ "$pane_cmd" = "codex" ]; then
      codex_debug "find_pane: found codex pane: $pane"
      if [ -z "$codex_panes" ]; then
        codex_panes="$pane"
      else
        codex_panes="$codex_panes $pane"
      fi
    # Priority 2: Node process with Codex patterns (legacy/npm run)
    elif [ "$pane_cmd" = "node" ]; then
      local pane_content
      pane_content=$(codex_tmux capture-pane -t "$pane" -p -S -2000 2>/dev/null)
      # Check for: banner, prompt character, or typical output patterns
      if echo "$pane_content" | grep -q "│ >_ OpenAI Codex" || \
         echo "$pane_content" | grep -qE "^› |Worked for [0-9]+|You approved codex"; then
        codex_debug "find_pane: found codex (node) pane: $pane"
        if [ -z "$codex_panes" ]; then
          codex_panes="$pane"
        else
          codex_panes="$codex_panes $pane"
        fi
      fi
    fi
  done <<< "$pane_list"

  # Handle detection results
  if [ -n "$codex_panes" ]; then
    local pane_count
    pane_count=$(echo "$codex_panes" | wc -w | tr -d ' ')
    codex_debug "find_pane: found $pane_count codex pane(s): $codex_panes"

    if [ "$pane_count" -eq 1 ]; then
      found_pane=$(echo "$codex_panes" | tr -d ' ')
      echo "Auto-detected Codex pane: $found_pane" >&2
    else
      echo "Warning: Multiple Codex panes found ($pane_count): $codex_panes" >&2
      found_pane=$(echo "$codex_panes" | awk '{print $1}')
      echo "Using first pane: $found_pane" >&2
      echo "To use a different pane, delete tmp/codex-pane-id and retry" >&2
    fi

    # Save pane ID for future use
    echo "$found_pane" > "$pane_id_file"
    codex_debug "find_pane: saved pane ID to $pane_id_file"
    echo "Saved pane ID to $pane_id_file" >&2
    echo "$found_pane"
    return 0
  fi

  codex_debug "find_pane: no Codex pane found in any session pane"
  echo "No Codex pane found" >&2
  return 1
}

# ==============================================================================
# Locking Functions (for concurrent access prevention)
# ==============================================================================

# Acquire a lock for Codex communication
# Usage: codex_acquire_lock [lock_name]
# Returns: 0 if lock acquired, 1 if already locked
# Note: Lock is released automatically when the calling shell exits
codex_acquire_lock() {
  local lock_name="${1:-codex-send}"
  local lock_file="${CODEX_TMP_DIR:-./tmp}/${lock_name}.lock"

  codex_ensure_tmp_dir > /dev/null

  # Open lock file on fd 9
  exec 9>"$lock_file"

  # Try to acquire exclusive lock (non-blocking)
  if ! flock -n 9; then
    echo "Error: Another send operation is in progress" >&2
    return 1
  fi

  return 0
}

# Release the lock (usually automatic when shell exits)
# Usage: codex_release_lock
codex_release_lock() {
  # Close fd 9 to release the lock
  exec 9>&- 2>/dev/null || true
}

# ==============================================================================
# Input Clear Function
# ==============================================================================

# Clear the input line in a pane (useful before sending new prompts)
# Usage: codex_clear_input "pane_id"
# Sends Ctrl+U to clear the current input line
codex_clear_input() {
  local pane_id="$1"

  if [ -z "$pane_id" ]; then
    echo "Error: pane_id required" >&2
    return 1
  fi

  # Send Ctrl+U to clear the input line
  codex_tmux send-keys -t "$pane_id" C-u
  sleep 0.1
  return 0
}

# ==============================================================================
# Prompt Sending Functions
# ==============================================================================

# Send prompt to Codex pane using paste-buffer (reliable multi-line)
# Usage: codex_send_prompt "$PANE_ID" "$PROMPT_CONTENT"
# Returns: 0 on success, 1 on failure
# Note: For long prompts (>1000 chars), use codex_send_prompt_file instead
codex_send_prompt() {
  local pane_id="$1"
  local prompt_content="$2"
  local marker_id="${3:-$(date +%s)-$RANDOM}"

  if [ -z "$pane_id" ] || [ -z "$prompt_content" ]; then
    echo "Error: pane_id and prompt_content required" >&2
    return 1
  fi

  # Check if pane is ready for input (not in copy mode, not dead)
  local pane_mode
  pane_mode=$(tmux display-message -t "$pane_id" -p '#{pane_in_mode}' 2>/dev/null)
  if [ "$pane_mode" = "1" ]; then
    # Pane is in copy mode, try to exit
    tmux send-keys -t "$pane_id" q 2>/dev/null
    sleep 0.2
  fi

  # Clear any existing input in the pane first
  codex_clear_input "$pane_id" 2>/dev/null || true

  local end_marker="<<RESPONSE_END_${marker_id}>>"

  # Add marker instruction to prompt
  local full_prompt="${prompt_content}

When finished, output exactly: ${end_marker}"

  # Create temporary file in project tmp directory
  local tmp_dir
  tmp_dir=$(codex_ensure_tmp_dir)
  local temp_prompt="${tmp_dir}/codex-prompt-$$"
  echo "$full_prompt" > "$temp_prompt"

  # Use named buffer to avoid conflicts with default buffer
  # Delete any existing buffer with this name first
  local buffer_name="codex-prompt-$$"
  tmux delete-buffer -b "$buffer_name" 2>/dev/null || true

  # Send using named buffer for reliable multi-line input
  tmux load-buffer -b "$buffer_name" "$temp_prompt"
  tmux paste-buffer -b "$buffer_name" -t "$pane_id" -d

  # Wait for paste to complete by checking if prompt tail appears in pane
  # This is more reliable than a fixed sleep
  local tail_check="${full_prompt: -32}"  # Last 32 chars of prompt
  local paste_timeout=40  # Longer timeout for potentially large prompts
  local tail_out=""
  for _ in $(seq 1 $paste_timeout); do
    tail_out=$(tmux capture-pane -t "$pane_id" -p -S -5 2>/dev/null)
    if echo "$tail_out" | grep -qF "$tail_check"; then
      break
    fi
    sleep 0.05
  done

  tmux send-keys -t "$pane_id" Enter

  rm -f "$temp_prompt"

  # Output marker for caller to use
  echo "$end_marker"
  return 0
}

# ==============================================================================
# File Reference Prompt Sending
# ==============================================================================

# Send a short prompt that references instruction file by path
# This avoids paste-buffer corruption for long prompts
# Usage: codex_send_prompt_file "$PANE_ID" "$INSTRUCTION_FILE" [end_marker] "file1.sh" "file2.sh" ...
# Returns: End marker on success, empty on failure
#
# The instruction file should contain detailed instructions in markdown format.
# Codex will read the instruction file and apply it to the target files.
#
# If end_marker is provided (starts with <<), it will be used instead of generating a new one.
#
# Example instruction file (.codex-prompt.md):
#   ## Review Instructions
#   1. Check for set -u compatibility
#   2. Check for set -e compatibility
#
#   ## Expected Output
#   PASS / FAIL / CONDITIONAL with details
#
codex_send_prompt_file() {
  local pane_id="$1"
  local instruction_file="$2"
  shift 2

  # Check if third argument is an end_marker (starts with <<)
  local end_marker=""
  local target_files=()
  if [[ "${1:-}" == "<<"* ]]; then
    end_marker="$1"
    shift
  fi
  target_files=("$@")

  # Generate marker if not provided
  if [ -z "$end_marker" ]; then
    local marker_id="${CODEX_MARKER_ID:-$(date +%s)-$RANDOM}"
    end_marker="<<RESPONSE_END_${marker_id}>>"
  fi

  if [ -z "$pane_id" ]; then
    echo "Error: pane_id required" >&2
    return 1
  fi

  if [ -z "$instruction_file" ]; then
    echo "Error: instruction_file required" >&2
    return 1
  fi

  # Check if pane is ready for input (not in copy mode, not dead)
  local pane_mode
  pane_mode=$(tmux display-message -t "$pane_id" -p '#{pane_in_mode}' 2>/dev/null)
  if [ "$pane_mode" = "1" ]; then
    # Pane is in copy mode, try to exit
    tmux send-keys -t "$pane_id" q 2>/dev/null
    sleep 0.2
  fi

  # Clear any existing input in the pane first
  codex_clear_input "$pane_id" 2>/dev/null || true

  # Build the short prompt
  local prompt="Please read the instructions in ${instruction_file} and apply them"

  if [ ${#target_files[@]} -gt 0 ]; then
    prompt="${prompt} to the following files:"
    for file in "${target_files[@]}"; do
      prompt="${prompt}
- ${file}"
    done
  else
    prompt="${prompt}."
  fi

  # Add marker instruction as a separate, emphasized part of the prompt
  # This keeps the marker instruction in the direct prompt rather than in the instruction file
  prompt="${prompt}

---
IMPORTANT: After completing your response, output this exact marker on its own line:
${end_marker}"

  # Create temporary file in project tmp directory
  local tmp_dir
  tmp_dir=$(codex_ensure_tmp_dir)
  local temp_prompt="${tmp_dir}/codex-prompt-file-$$"
  echo "$prompt" > "$temp_prompt"

  # Use named buffer to avoid conflicts with default buffer
  # Delete any existing buffer with this name first
  local buffer_name="codex-file-$$"
  tmux delete-buffer -b "$buffer_name" 2>/dev/null || true

  # Send using named buffer for reliable multi-line input
  # -d flag deletes buffer after pasting
  tmux load-buffer -b "$buffer_name" "$temp_prompt"
  tmux paste-buffer -b "$buffer_name" -t "$pane_id" -d

  # Wait for paste to complete by checking if prompt tail appears in pane
  # This is more reliable than a fixed sleep
  local tail_check="${prompt: -32}"  # Last 32 chars of prompt
  local paste_timeout=20
  local tail_out=""
  for _ in $(seq 1 $paste_timeout); do
    tail_out=$(tmux capture-pane -t "$pane_id" -p -S -5 2>/dev/null)
    if echo "$tail_out" | grep -qF "$tail_check"; then
      break
    fi
    sleep 0.05
  done

  tmux send-keys -t "$pane_id" Enter

  rm -f "$temp_prompt"

  # Output marker for caller to use
  echo "$end_marker"
  return 0
}

# ==============================================================================
# Chunked Prompt Sending (for long prompts stability)
# ==============================================================================

# Low-level function: Send long text in chunks (UTF-8 safe)
# Usage: codex_send_chunked "$PANE_ID" "$TEXT" [chunk_size] [delay]
# Note: This sends text only, does NOT send Enter key
# Note: Newlines within chunks are preserved and sent as-is via send-keys -l
codex_send_chunked() {
  local pane_id="$1"
  local text="$2"
  local chunk_size="${3:-${CODEX_CHUNK_SIZE:-200}}"
  local delay="${4:-${CODEX_CHUNK_DELAY:-0.02}}"

  if [ -z "$pane_id" ] || [ -z "$text" ]; then
    echo "Error: pane_id and text required" >&2
    return 1
  fi

  # Build tmux command as array for safe execution (handles paths with spaces)
  local -a tmux_cmd=(tmux)
  if [ -n "${CODEX_TMUX_SOCKET:-}" ]; then
    tmux_cmd=(tmux -S "$CODEX_TMUX_SOCKET")
  fi

  codex_debug "send_chunked: sending ${#text} chars in chunks of $chunk_size with ${delay}s delay"

  # Determine locale for UTF-8 safe processing
  # Try common UTF-8 locales, fallback to C (byte-based splitting)
  local utf8_locale="C"
  local loc
  for loc in "C.UTF-8" "en_US.UTF-8" "UTF-8"; do
    if locale -a 2>/dev/null | grep -qiE "^${loc}$"; then
      utf8_locale="$loc"
      codex_debug "send_chunked: using locale $utf8_locale for UTF-8 safe splitting"
      break
    fi
  done

  if [ "$utf8_locale" = "C" ]; then
    codex_debug "send_chunked: No UTF-8 locale found, using byte-based splitting (may break multibyte chars)"
  fi

  # Split text into chunks using awk with NUL separator for reliable reading
  # This preserves:
  # - Empty chunks (whitespace-only sections)
  # - Newlines within the text (reconstructed in awk)
  # - Multibyte characters (with proper UTF-8 locale)
  local chunk
  local chunk_count=0

  while IFS= read -r -d '' chunk || [ -n "$chunk" ]; do
    # Send chunk (including those with newlines - send-keys -l handles them)
    "${tmux_cmd[@]}" send-keys -t "$pane_id" -l -- "$chunk"
    chunk_count=$((chunk_count + 1))
    # Only sleep if delay is non-zero
    [ "$delay" != "0" ] && sleep "$delay"
  done < <(printf '%s' "$text" | LC_ALL="$utf8_locale" awk -v size="$chunk_size" '
    BEGIN {
      ORS = "\0"  # NUL separator for reliable bash read
      content = ""
    }
    {
      # Reconstruct full text with newlines preserved
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

  codex_debug "send_chunked: sent $chunk_count chunks"
  return 0
}

# Send prompt to Codex using chunked method (for long prompts stability)
# Usage: codex_send_prompt_chunked "$PANE_ID" "$PROMPT_CONTENT" [marker_id]
# Arguments:
#   pane_id        - Target tmux pane ID (e.g., %1)
#   prompt_content - The prompt text to send
#   marker_id      - Optional custom marker ID (default: timestamp-random)
# Returns: End marker string on success (use with codex_wait_completion)
# Note: This is more stable for long prompts (>1000 chars) than codex_send_prompt
# Note: Inherits chunk_size/delay from CODEX_CHUNK_SIZE/CODEX_CHUNK_DELAY env vars
codex_send_prompt_chunked() {
  local pane_id="$1"
  local prompt_content="$2"
  local marker_id="${3:-$(date +%s)-$RANDOM}"

  if [ -z "$pane_id" ] || [ -z "$prompt_content" ]; then
    echo "Error: pane_id and prompt_content required" >&2
    return 1
  fi

  # Build tmux command as array for safe execution
  local -a tmux_cmd=(tmux)
  if [ -n "${CODEX_TMUX_SOCKET:-}" ]; then
    tmux_cmd=(tmux -S "$CODEX_TMUX_SOCKET")
  fi

  # Check if pane is ready for input (not in copy mode)
  local pane_mode
  pane_mode=$("${tmux_cmd[@]}" display-message -t "$pane_id" -p '#{pane_in_mode}' 2>/dev/null)
  if [ "$pane_mode" = "1" ]; then
    # Pane is in copy mode, try to exit
    "${tmux_cmd[@]}" send-keys -t "$pane_id" q 2>/dev/null
    sleep 0.2
  fi

  # Clear any existing input in the pane first
  codex_clear_input "$pane_id" 2>/dev/null || true

  local end_marker="<<RESPONSE_END_${marker_id}>>"

  # Add marker instruction to prompt
  local full_prompt="${prompt_content}

When finished, output exactly: ${end_marker}"

  codex_debug "send_prompt_chunked: sending ${#full_prompt} chars to pane $pane_id"

  # Send using chunked method
  codex_send_chunked "$pane_id" "$full_prompt"

  # Wait for chunks to be processed by checking if prompt tail appears in pane
  # Use byte-based comparison with LC_ALL=C to avoid UTF-8 multibyte issues
  local tail_check
  tail_check=$(printf '%s' "$full_prompt" | LC_ALL=C tail -c 64)  # Last 64 bytes
  local paste_timeout=60  # 60 * 0.05 = 3s max wait
  local tail_out=""
  local paste_complete=false

  codex_debug "send_prompt_chunked: waiting for prompt tail (${#tail_check} bytes)"

  for _ in $(seq 1 $paste_timeout); do
    tail_out=$("${tmux_cmd[@]}" capture-pane -t "$pane_id" -p -S -8 2>/dev/null)
    if printf '%s' "$tail_out" | LC_ALL=C grep -qF "$tail_check"; then
      paste_complete=true
      break
    fi
    sleep 0.05
  done

  if [ "$paste_complete" = false ]; then
    codex_debug "send_prompt_chunked: WARNING - tail check timeout after 3s, proceeding anyway"
  fi

  # Send Enter only after tail appears (or timeout)
  "${tmux_cmd[@]}" send-keys -t "$pane_id" Enter

  codex_debug "send_prompt_chunked: Enter sent, marker: $end_marker"

  # Output marker for caller to use
  echo "$end_marker"
  return 0
}

# ==============================================================================
# Completion Detection Functions (Polling)
# ==============================================================================

# Wait for Codex completion using marker + idle detection (polling)
# Usage: codex_wait_completion "$PANE_ID" "$END_MARKER" ["$BEFORE_HASH"]
# Returns: 0 if completed, 1 if timeout
codex_wait_completion() {
  local pane_id="$1"
  local end_marker="$2"
  local before_hash="${3:-}"
  local wait_timeout="${CODEX_WAIT_TIMEOUT:-180}"
  local poll_interval="${CODEX_POLL_INTERVAL:-2}"
  local idle_threshold="${CODEX_IDLE_THRESHOLD:-5}"
  local capture_lines="${CODEX_CAPTURE_LINES:-5000}"

  codex_debug "wait_completion: pane=$pane_id, marker=$end_marker"

  # Check if we're in tmux
  if [ -z "${TMUX:-}" ] && [ -z "${CODEX_TMUX_SOCKET:-}" ]; then
    codex_debug "wait_completion: not in tmux environment"
    echo "Warning: Not in tmux environment, completion detection may not work" >&2
    return 1
  fi

  # First, do a quick check if marker is already present
  local current_output
  current_output=$(tmux capture-pane -t "$pane_id" -p -S -5000 2>/dev/null)
  if echo "$current_output" | grep -qF "$end_marker"; then
    codex_debug "wait_completion: marker already present in output"
    echo "Codex response completed (marker found)" >&2
    return 0
  fi

  local completed=false
  local idle_count=0
  local last_hash="$before_hash"

  codex_debug "wait_completion: starting polling loop (timeout: ${wait_timeout}s, interval: ${poll_interval}s)"
  echo "Waiting for Codex response (polling, timeout: ${wait_timeout}s)..." >&2

  local max_polls=$((wait_timeout / poll_interval))
  for i in $(seq 1 "$max_polls"); do
    current_output=$(tmux capture-pane -t "$pane_id" -p -S "-$capture_lines" 2>/dev/null)
    local current_hash
    current_hash=$(echo "$current_output" | codex_hash_content)

    # Check for completion marker
    if echo "$current_output" | grep -qF "$end_marker"; then
      codex_debug "wait_completion: marker found at poll $i"
      echo "Codex response completed (marker found)" >&2
      completed=true
      break
    fi

    # Hash-based idle detection (fallback)
    if [ "$current_hash" = "$last_hash" ]; then
      idle_count=$((idle_count + 1))
      if [ "$idle_count" -ge "$idle_threshold" ]; then
        # Check if Codex appears to be at prompt (ready for input)
        if echo "$current_output" | tail -3 | grep -qE '^>\s*$|^codex>\s*$|^\[codex\]'; then
          codex_debug "wait_completion: idle detected at poll $i"
          echo "Codex appears idle (marker not found, using idle detection)" >&2
          completed=true
          break
        fi
      fi
    else
      idle_count=0
      last_hash="$current_hash"
    fi

    sleep "$poll_interval"
  done

  if [ "$completed" = true ]; then
    return 0
  else
    codex_debug "wait_completion: timeout after ${wait_timeout}s"
    echo "Warning: Timeout after ${wait_timeout}s - response may be incomplete" >&2
    return 1
  fi
}

# ==============================================================================
# Output Capture Functions
# ==============================================================================

# Capture Codex pane output to file
# Usage: codex_capture_output "$PANE_ID" ["$OUTPUT_FILE"]
codex_capture_output() {
  local pane_id="$1"
  local output_file="${2:-$(codex_tmp_path codex-attach-capture.txt)}"
  local capture_lines="${CODEX_CAPTURE_LINES:-5000}"

  tmux capture-pane -t "$pane_id" -p -S "-$capture_lines" > "$output_file"
  echo "$output_file"
}

# ==============================================================================
# Utility Functions
# ==============================================================================

# Check if running inside tmux
# Usage: codex_check_tmux
# Returns: 0 if in tmux, 1 otherwise
codex_check_tmux() {
  if [ -z "${TMUX:-}" ]; then
    echo "Error: Not inside a tmux session. Run 'tmux' first." >&2
    return 1
  fi
  return 0
}

# Generate unique signal/marker ID
# Usage: SIGNAL=$(codex_generate_signal "prefix")
codex_generate_signal() {
  local prefix="${1:-codex}"
  echo "${prefix}-$$-$(date +%s)-$RANDOM"
}

# ==============================================================================
# Interactive Pane Launch Functions
# ==============================================================================

# Launch Codex in interactive mode in a new tmux pane
# Usage: pane_id=$(codex_launch_interactive_pane [sandbox_mode])
# Arguments:
#   sandbox_mode - Optional: read-only | workspace-write | danger-full-access (default: read-only)
# Returns: New pane ID on success, empty on failure
# Side effects: Saves pane ID to tmp/codex-pane-id
#
# This function:
# 1. Splits the current tmux window horizontally
# 2. Launches `codex` (interactive mode) in the new pane
# 3. Waits for Codex to initialize (detects banner)
# 4. Saves the pane ID for future reuse
codex_launch_interactive_pane() {
  local sandbox_mode="${1:-read-only}"
  local pane_id_file="${2:-$(codex_tmp_path codex-pane-id)}"

  # Build tmux command (handles socket option)
  local -a tmux_cmd=(tmux)
  if [ -n "${CODEX_TMUX_SOCKET:-}" ]; then
    tmux_cmd=(tmux -S "$CODEX_TMUX_SOCKET")
  fi

  # Check if we're in tmux
  if [ -z "${TMUX:-}" ] && [ -z "${CODEX_TMUX_SOCKET:-}" ]; then
    echo "Error: Not inside a tmux session" >&2
    return 1
  fi

  # Check if codex command is available
  if ! command -v codex &>/dev/null; then
    echo "Error: codex command not found" >&2
    return 1
  fi

  codex_debug "launch_interactive: sandbox=$sandbox_mode"

  # Capture original pane ID to ensure focus returns after split
  local original_pane
  original_pane=$("${tmux_cmd[@]}" display-message -p '#{pane_id}')

  # Get current working directory
  local work_dir
  work_dir=$(pwd)

  # Split window horizontally and launch Codex in interactive mode
  # Use -P -F to directly capture the new pane ID (more reliable than list-panes filtering)
  local new_pane
  new_pane=$("${tmux_cmd[@]}" split-window -h -d -c "$work_dir" -P -F '#{pane_id}' "codex -s $sandbox_mode")

  if [ -z "$new_pane" ]; then
    echo "Error: Failed to get new pane ID" >&2
    return 1
  fi

  codex_debug "launch_interactive: new_pane=$new_pane, waiting for initialization"

  # Wait for Codex to initialize (detect banner or prompt)
  local init_timeout=30
  local init_success=false
  for i in $(seq 1 $init_timeout); do
    local pane_content
    pane_content=$("${tmux_cmd[@]}" capture-pane -t "$new_pane" -p -S -50 2>/dev/null)

    # Check for Codex banner or prompt character
    if echo "$pane_content" | grep -qE "│ >_ OpenAI Codex|^› "; then
      codex_debug "launch_interactive: Codex initialized after ${i}s"
      init_success=true
      break
    fi

    sleep 1
  done

  if [ "$init_success" != true ]; then
    echo "Warning: Codex initialization timeout after ${init_timeout}s, proceeding anyway" >&2
    # Still proceed - pane exists and codex may have a different banner format
  fi

  # Save pane ID for future reuse
  codex_ensure_tmp_dir > /dev/null
  echo "$new_pane" > "$pane_id_file"
  codex_debug "launch_interactive: saved pane ID to $pane_id_file"

  # Ensure focus returns to original pane
  "${tmux_cmd[@]}" select-pane -t "$original_pane"

  echo "$new_pane"
  return 0
}

# Get or create a Codex pane (unified entry point)
# Usage: pane_id=$(codex_get_or_create_pane [sandbox_mode])
# This function:
# 1. First tries to find an existing Codex pane (codex_find_pane, which internally verifies)
# 2. If not found or invalid, launches a new interactive pane (codex_launch_interactive_pane)
# Returns: Pane ID on success, empty on failure
codex_get_or_create_pane() {
  local sandbox_mode="${1:-read-only}"
  local pane_id_file="${2:-$(codex_tmp_path codex-pane-id)}"

  codex_debug "get_or_create: checking for existing pane"

  # Try to find existing pane
  # Note: codex_find_pane already calls codex_verify_pane internally,
  # so we trust its result to avoid race conditions from double verification
  local existing_pane
  existing_pane=$(codex_find_pane "$pane_id_file" 2>/dev/null)

  if [ -n "$existing_pane" ]; then
    # codex_find_pane already verified the pane, trust the result
    codex_debug "get_or_create: found verified existing pane $existing_pane"
    echo "$existing_pane"
    return 0
  fi

  codex_debug "get_or_create: no existing pane, launching new one"
  echo "No existing Codex pane found, launching new instance..." >&2

  # Launch new interactive pane
  local new_pane
  new_pane=$(codex_launch_interactive_pane "$sandbox_mode" "$pane_id_file")

  if [ -n "$new_pane" ]; then
    echo "Launched new Codex pane: $new_pane" >&2
    echo "$new_pane"
    return 0
  else
    echo "Error: Failed to launch Codex pane" >&2
    return 1
  fi
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
