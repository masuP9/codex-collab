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

# Temporary directory for all working files
: "${CODEX_TMP_DIR:=./tmp}"

# Project-local tmux socket (for bidirectional communication)
# When set, all tmux commands use this socket instead of default
: "${CODEX_TMUX_SOCKET:=}"          # e.g., "./collab.sock"

# Buffer names for communication
: "${CODEX_BUFFER_RESPONSE:=codex-response}"
: "${CODEX_BUFFER_STATUS:=codex-status}"

# Signal channel name for wait-for
: "${CODEX_SIGNAL_CHANNEL:=codex-done}"

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

# Ensure tmp directory exists
# Usage: codex_ensure_tmp_dir
codex_ensure_tmp_dir() {
  local tmp_dir="${CODEX_TMP_DIR:-./tmp}"
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

  # Use codex_tmux_cmd for socket support
  local tmux_cmd
  tmux_cmd=$(codex_tmux_cmd)
  codex_debug "verify_pane: checking pane $pane_id with: $tmux_cmd"

  # Check if pane exists using direct query (more reliable than list-panes + grep)
  # display-message -t returns empty string for non-existent panes
  local queried_pane
  queried_pane=$($tmux_cmd display-message -t "$pane_id" -p '#{pane_id}' 2>/dev/null)
  if [ -z "$queried_pane" ] || [ "$queried_pane" != "$pane_id" ]; then
    codex_debug "verify_pane: pane $pane_id not found (queried: '$queried_pane')"
    echo "error:pane_not_found"
    return 1
  fi

  # CRITICAL: Verify pane belongs to current session
  # display-message -t can access panes from ANY session, so we must explicitly check
  local current_session pane_session
  current_session=$($tmux_cmd display-message -p '#{session_id}' 2>/dev/null)
  pane_session=$($tmux_cmd display-message -t "$pane_id" -p '#{session_id}' 2>/dev/null)
  if [ "$pane_session" != "$current_session" ]; then
    codex_debug "verify_pane: pane $pane_id belongs to different session (pane: $pane_session, current: $current_session)"
    echo "error:wrong_session"
    return 1
  fi

  # Check if pane is running Codex
  local pane_cmd
  pane_cmd=$($tmux_cmd display-message -t "$pane_id" -p '#{pane_current_command}' 2>/dev/null)
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
    pane_content=$($tmux_cmd capture-pane -t "$pane_id" -p -S -2000 2>/dev/null)

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

  # Use codex_tmux_cmd for socket support
  local tmux_cmd
  tmux_cmd=$(codex_tmux_cmd)
  codex_debug "find_pane: using tmux command: $tmux_cmd"

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
  pane_list=$($tmux_cmd list-panes -s -F '#{pane_id}' 2>&1)
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
    pane_cmd=$($tmux_cmd display-message -t "$pane" -p '#{pane_current_command}' 2>/dev/null)
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
      pane_content=$($tmux_cmd capture-pane -t "$pane" -p -S -2000 2>/dev/null)
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
      echo "To use a different pane, set tmp/codex-pane-id manually or use /collab-attach" >&2
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
  codex_ensure_tmp_dir > /dev/null
  local temp_prompt="$(pwd)/${CODEX_TMP_DIR:-tmp}/codex-prompt-$$"
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
# File-based Prompt Sending (Hybrid Method)
# ==============================================================================

# Send a short prompt that references instruction file and target files
# This avoids paste-buffer corruption for long prompts
# Usage: codex_send_prompt_file "$PANE_ID" "$INSTRUCTION_FILE" "file1.sh" "file2.sh" ...
# Returns: End marker on success, empty on failure
#
# The instruction file should contain detailed instructions in markdown format.
# Codex will read the instruction file and apply it to the target files.
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
  local target_files=("$@")
  local marker_id="${CODEX_MARKER_ID:-$(date +%s)-$RANDOM}"

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

  local end_marker="<<RESPONSE_END_${marker_id}>>"

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
  codex_ensure_tmp_dir > /dev/null
  local temp_prompt="$(pwd)/${CODEX_TMP_DIR:-tmp}/codex-prompt-file-$$"
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
# Completion Detection Functions
# ==============================================================================

# Wait for Codex completion using marker + idle detection
# Usage: codex_wait_completion "$PANE_ID" "$END_MARKER" "$BEFORE_HASH"
# Returns: 0 if completed, 1 if timeout
codex_wait_completion() {
  local pane_id="$1"
  local end_marker="$2"
  local before_hash="${3:-}"
  local wait_timeout="${CODEX_WAIT_TIMEOUT:-180}"
  local poll_interval="${CODEX_POLL_INTERVAL:-2}"
  local idle_threshold="${CODEX_IDLE_THRESHOLD:-5}"
  local capture_lines="${CODEX_CAPTURE_LINES:-5000}"

  local completed=false
  local idle_count=0
  local last_hash="$before_hash"

  echo "Waiting for Codex response (timeout: ${wait_timeout}s)..." >&2

  local max_polls=$((wait_timeout / poll_interval))
  for i in $(seq 1 "$max_polls"); do
    local current_output
    current_output=$(tmux capture-pane -t "$pane_id" -p -S "-$capture_lines" 2>/dev/null)
    local current_hash
    current_hash=$(echo "$current_output" | codex_hash_content)

    # Check for completion marker
    if echo "$current_output" | grep -qF "$end_marker"; then
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
# Tmux Socket Helper
# ==============================================================================

# Get tmux command with optional socket
# Usage: cmd=$(codex_tmux_cmd)
#        $cmd list-panes
codex_tmux_cmd() {
  if [ -n "${CODEX_TMUX_SOCKET:-}" ]; then
    echo "tmux -S $CODEX_TMUX_SOCKET"
  else
    echo "tmux"
  fi
}

# ==============================================================================
# Buffer-based Communication (Codex → Claude)
# ==============================================================================

# Set data to tmux buffer
# Usage: codex_set_buffer "buffer-name" "data"
# This is typically called from Codex side
codex_set_buffer() {
  local buffer_name="${1:-$CODEX_BUFFER_RESPONSE}"
  local data="$2"
  local tmux_cmd
  tmux_cmd=$(codex_tmux_cmd)

  $tmux_cmd set-buffer -b "$buffer_name" "$data"
}

# Get data from tmux buffer
# Usage: data=$(codex_get_buffer "buffer-name")
# This is typically called from Claude side
codex_get_buffer() {
  local buffer_name="${1:-$CODEX_BUFFER_RESPONSE}"
  local tmux_cmd
  tmux_cmd=$(codex_tmux_cmd)

  $tmux_cmd show-buffer -b "$buffer_name" 2>/dev/null
}

# Check if buffer exists and has content
# Usage: if codex_buffer_exists "buffer-name"; then ...
codex_buffer_exists() {
  local buffer_name="${1:-$CODEX_BUFFER_RESPONSE}"
  local tmux_cmd
  tmux_cmd=$(codex_tmux_cmd)

  $tmux_cmd show-buffer -b "$buffer_name" &>/dev/null
}

# Clear a buffer
# Usage: codex_clear_buffer "buffer-name"
codex_clear_buffer() {
  local buffer_name="${1:-$CODEX_BUFFER_RESPONSE}"
  local tmux_cmd
  tmux_cmd=$(codex_tmux_cmd)

  $tmux_cmd delete-buffer -b "$buffer_name" 2>/dev/null || true
}

# ==============================================================================
# Signal-based Completion (Event-driven using wait-for)
# ==============================================================================

# Send signal to wake up waiting process
# Usage: codex_send_signal "channel-name"
# This is typically called from Codex side after completing a task
codex_send_signal() {
  local channel="${1:-$CODEX_SIGNAL_CHANNEL}"
  local tmux_cmd
  tmux_cmd=$(codex_tmux_cmd)

  $tmux_cmd wait-for -S "$channel"
}

# Wait for signal (blocking)
# Usage: codex_wait_signal "channel-name"
# This is typically called from Claude side
# NOTE: This blocks until signal is received. Use with timeout or background.
codex_wait_signal() {
  local channel="${1:-$CODEX_SIGNAL_CHANNEL}"
  local tmux_cmd
  tmux_cmd=$(codex_tmux_cmd)

  $tmux_cmd wait-for "$channel"
}

# Wait for signal with timeout
# Usage: if codex_wait_signal_timeout "channel" 30; then echo "received"; fi
# Returns: 0 if signal received, 1 if timeout
codex_wait_signal_timeout() {
  local channel="${1:-$CODEX_SIGNAL_CHANNEL}"
  local timeout="${2:-$CODEX_WAIT_TIMEOUT}"
  local tmux_cmd
  tmux_cmd=$(codex_tmux_cmd)

  # Run wait-for in background and wait with timeout
  $tmux_cmd wait-for "$channel" &
  local wait_pid=$!

  local elapsed=0
  while kill -0 $wait_pid 2>/dev/null; do
    if [ "$elapsed" -ge "$timeout" ]; then
      kill $wait_pid 2>/dev/null || true
      return 1
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  wait $wait_pid 2>/dev/null
  return 0
}

# ==============================================================================
# Combined Communication Pattern
# ==============================================================================

# Wait for Codex response using signal + buffer (event-driven)
# Usage: response=$(codex_wait_response "channel" "buffer" 60)
# Returns: Buffer content if signal received, empty if timeout
codex_wait_response() {
  local channel="${1:-$CODEX_SIGNAL_CHANNEL}"
  local buffer="${2:-$CODEX_BUFFER_RESPONSE}"
  local timeout="${3:-$CODEX_WAIT_TIMEOUT}"

  echo "Waiting for Codex signal (timeout: ${timeout}s)..." >&2

  if codex_wait_signal_timeout "$channel" "$timeout"; then
    echo "Signal received, reading response..." >&2
    codex_get_buffer "$buffer"
    return 0
  else
    echo "Timeout waiting for Codex response" >&2
    return 1
  fi
}

# Codex-side: Send response and signal completion
# Usage: codex_respond "response data" "channel" "buffer"
# This is a convenience function for Codex to use
codex_respond() {
  local data="$1"
  local channel="${2:-$CODEX_SIGNAL_CHANNEL}"
  local buffer="${3:-$CODEX_BUFFER_RESPONSE}"

  codex_set_buffer "$buffer" "$data"
  codex_send_signal "$channel"
}

# ==============================================================================
# Paste-buffer Based Communication (TUI-safe)
# ==============================================================================
#
# These functions use paste-buffer + send-keys Enter for reliable communication
# between TUI applications (Claude Code, Codex). Direct send-keys with text+Enter
# doesn't work for TUI apps because Enter is interpreted as newline, not submit.
#
# The paste-buffer method:
# 1. Write content to a temp file
# 2. Load file into tmux buffer (load-buffer)
# 3. Paste buffer to target pane (paste-buffer)
# 4. Send Enter key separately (send-keys Enter)
#

# Send message to any pane using paste-buffer method (TUI-safe)
# Usage: codex_send_to_pane "target_pane_id" "message"
# This works for both shell and TUI (Claude Code, Codex) targets
codex_send_to_pane() {
  local target_pane="$1"
  local message="$2"
  local tmux_cmd
  tmux_cmd=$(codex_tmux_cmd)

  if [ -z "$target_pane" ] || [ -z "$message" ]; then
    echo "Error: target_pane and message required" >&2
    return 1
  fi

  # Create temp file in project tmp directory
  codex_ensure_tmp_dir > /dev/null
  local temp_file="$(pwd)/${CODEX_TMP_DIR:-tmp}/codex-paste-$$-$RANDOM"
  echo "$message" > "$temp_file"

  # Load to buffer, paste, then send Enter
  $tmux_cmd load-buffer "$temp_file"
  $tmux_cmd paste-buffer -t "$target_pane"
  sleep 0.3
  $tmux_cmd send-keys -t "$target_pane" Enter

  rm -f "$temp_file"
  return 0
}

# Send message from Codex to Claude Code pane
# Usage: codex_send_to_claude "claude_pane_id" "message"
# Convenience wrapper for Codex-side use
codex_send_to_claude() {
  local claude_pane="$1"
  local message="$2"

  codex_send_to_pane "$claude_pane" "$message"
}

# Send message from Claude to Codex pane (alternative to codex_send_prompt)
# Usage: codex_send_to_codex "codex_pane_id" "message"
# Convenience wrapper for Claude-side use
codex_send_to_codex() {
  local codex_pane="$1"
  local message="$2"

  codex_send_to_pane "$codex_pane" "$message"
}

# Clear the input line in a pane (useful before sending new prompts)
# Usage: codex_clear_input "pane_id"
# Sends Ctrl+U to clear the current input line
codex_clear_input() {
  local pane_id="$1"
  local tmux_cmd
  tmux_cmd=$(codex_tmux_cmd)

  if [ -z "$pane_id" ]; then
    echo "Error: pane_id required" >&2
    return 1
  fi

  # Send Ctrl+U to clear the input line
  $tmux_cmd send-keys -t "$pane_id" C-u
  sleep 0.1
  return 0
}

# ==============================================================================
# Codex Approval Automation
# ==============================================================================
#
# Functions to automatically approve Codex command execution dialogs
# after verifying the command matches expected patterns.
#

# Check if Codex is showing an ACTIVE approval dialog and extract the command
# Usage: cmd=$(codex_get_pending_command "codex_pane_id")
# Returns: The command waiting for approval, or empty if no active dialog
#
# Key insight: An ACTIVE dialog has "Press enter to confirm" or "› 1. Yes, proceed"
# in the last few lines. Old dialogs in scroll history won't have this.
codex_get_pending_command() {
  local codex_pane="${1:-}"

  # Validate required argument
  if [ -z "$codex_pane" ]; then
    echo "Error: codex_pane is required" >&2
    return 1
  fi

  local tmux_socket="${CODEX_TMUX_SOCKET:-}"

  # Build tmux command as array for safe execution
  local -a tmux_cmd=(tmux)
  if [ -n "$tmux_socket" ]; then
    tmux_cmd=(tmux -S "$tmux_socket")
  fi

  # Capture last 30 lines with -J to join wrapped lines
  # -J prevents long commands from being split across multiple lines
  local pane_content
  pane_content=$("${tmux_cmd[@]}" capture-pane -t "$codex_pane" -p -J -S -30 2>/dev/null)

  # Check for ACTIVE dialog indicators in the last few lines
  # Active dialogs show "Press enter to confirm" or "› 1. Yes, proceed" at the bottom
  local last_lines
  last_lines=$(echo "$pane_content" | tail -10)

  if ! echo "$last_lines" | grep -qE "Press enter to confirm|› 1\. Yes, proceed"; then
    # No active dialog
    return 1
  fi

  # Now check for the full dialog pattern
  if ! echo "$pane_content" | grep -q "Would you like to run the following command?"; then
    return 1
  fi

  # Extract the command (line starting with $ after dialog prompt)
  # Use tail -1 to get the LATEST $ line (in case of multiple dialogs in history)
  # The captured content is already limited to last 30 lines, so this is safe
  echo "$pane_content" | grep -E '^\s*\$ ' | sed 's/^\s*\$ //' | tail -1
}

# Approve Codex command if it matches expected pattern
# Usage: codex_approve_if_matches "codex_pane_id" "pattern"
# Returns: 0 if approved, 1 if no dialog or pattern mismatch
#
# Examples:
#   codex_approve_if_matches "%4" "tmux.*set-buffer"
#   codex_approve_if_matches "%4" "tmux.*wait-for -S"
codex_approve_if_matches() {
  local codex_pane="${1:-}"
  local pattern="${2:-}"

  # Validate required arguments
  if [ -z "$codex_pane" ]; then
    echo "Error: codex_pane is required" >&2
    return 1
  fi
  if [ -z "$pattern" ]; then
    echo "Error: pattern is required (empty pattern would match everything)" >&2
    return 1
  fi

  local tmux_socket="${CODEX_TMUX_SOCKET:-}"

  # Build tmux command as array for safe execution
  local -a tmux_cmd=(tmux)
  if [ -n "$tmux_socket" ]; then
    tmux_cmd=(tmux -S "$tmux_socket")
  fi

  # Get pending command
  local pending_cmd
  pending_cmd=$(codex_get_pending_command "$codex_pane")

  if [ -z "$pending_cmd" ]; then
    echo "No approval dialog found" >&2
    return 1
  fi

  # Check if command matches pattern
  if echo "$pending_cmd" | grep -qE "$pattern"; then
    echo "Approving command: $pending_cmd" >&2
    "${tmux_cmd[@]}" send-keys -t "$codex_pane" y
    sleep 0.2
    "${tmux_cmd[@]}" send-keys -t "$codex_pane" Enter
    return 0
  else
    echo "Command does not match pattern '$pattern': $pending_cmd" >&2
    return 1
  fi
}

# Approve multiple Codex commands in sequence (for set-buffer + wait-for)
# Usage: codex_approve_response_commands "codex_pane_id" [timeout_seconds]
# Approves: tmux.*set-buffer and tmux.*wait-for -S commands
codex_approve_response_commands() {
  local codex_pane="${1:-}"
  local timeout="${2:-30}"
  local approved_count=0
  local elapsed=0

  # Validate required argument
  if [ -z "$codex_pane" ]; then
    echo "Error: codex_pane is required" >&2
    return 1
  fi

  # Validate timeout is a number, default to 30 if not
  if ! [[ "$timeout" =~ ^[0-9]+$ ]]; then
    echo "Warning: Invalid timeout '$timeout', using default 30" >&2
    timeout=30
  fi

  while [ "$elapsed" -lt "$timeout" ]; do
    # Try to approve set-buffer command
    if codex_approve_if_matches "$codex_pane" "tmux.*set-buffer.*-b"; then
      approved_count=$((approved_count + 1))
      sleep 1
      elapsed=$((elapsed + 1))
      continue
    fi

    # Try to approve wait-for -S command
    if codex_approve_if_matches "$codex_pane" "tmux.*wait-for.*-S"; then
      approved_count=$((approved_count + 1))
      sleep 1
      elapsed=$((elapsed + 1))
      continue
    fi

    # No approval dialog, wait a bit
    sleep 1
    elapsed=$((elapsed + 1))

    # If we've approved both commands, we're done
    if [ "$approved_count" -ge 2 ]; then
      echo "Approved $approved_count commands" >&2
      return 0
    fi
  done

  if [ "$approved_count" -gt 0 ]; then
    echo "Approved $approved_count commands (timeout reached)" >&2
    return 0
  else
    echo "No commands approved within ${timeout}s" >&2
    return 1
  fi
}

# ==============================================================================
# Collab Session Management
# ==============================================================================
#
# Functions to manage the collab tmux session with project-internal socket.
# This enables bidirectional communication between Claude Code and Codex.
#

# Start or attach to a collab session
# Usage: codex_collab_session_start [options]
# Options:
#   --socket PATH    Socket path (default: ./collab.sock)
#   --session NAME   Session name (default: collab)
#   --attach         Attach to session after creation (default: false)
#   --start-codex    Start Codex in right pane
#   --start-claude   Start Claude Code in left pane
#
# Returns: 0 on success, 1 on failure
# Outputs: Session info to stdout, pane IDs saved to tmp/codex-pane-id and tmp/claude-pane-id
codex_collab_session_start() {
  local socket="${CODEX_TMUX_SOCKET:-./collab.sock}"
  local session_name="collab"
  local do_attach=false
  local start_codex=false
  local start_claude=false

  # Parse arguments with value validation
  while [ $# -gt 0 ]; do
    case "$1" in
      --socket)
        if [ -z "${2:-}" ]; then
          echo "Error: --socket requires a value" >&2
          return 1
        fi
        socket="$2"
        shift 2
        ;;
      --session)
        if [ -z "${2:-}" ]; then
          echo "Error: --session requires a value" >&2
          return 1
        fi
        session_name="$2"
        shift 2
        ;;
      --attach)
        do_attach=true
        shift
        ;;
      --start-codex)
        start_codex=true
        shift
        ;;
      --start-claude)
        start_claude=true
        shift
        ;;
      *)
        echo "Unknown option: $1" >&2
        return 1
        ;;
    esac
  done

  # Check if session already exists
  if tmux -S "$socket" has-session -t "$session_name" 2>/dev/null; then
    echo "Session '$session_name' already exists on socket '$socket'"
    echo "Note: --start-codex/--start-claude flags are ignored for existing sessions"

    # Update pane ID files for existing session (use pane_index for reliable left/right detection)
    local claude_pane codex_pane
    claude_pane=$(tmux -S "$socket" list-panes -t "$session_name" -F '#{pane_index} #{pane_id}' | awk '$1==0 {print $2}')
    codex_pane=$(tmux -S "$socket" list-panes -t "$session_name" -F '#{pane_index} #{pane_id}' | awk '$1==1 {print $2}')

    # Check if expected panes exist
    if [ -z "$claude_pane" ] && [ -z "$codex_pane" ]; then
      echo "Warning: Expected 2-pane layout not found. Pane ID files not updated." >&2
      echo "Available panes:"
      tmux -S "$socket" list-panes -t "$session_name" -F '  #{pane_index}: #{pane_id}'
    else
      if [ -n "$claude_pane" ]; then
        echo "$claude_pane" > "$(codex_tmp_path claude-pane-id)"
        echo "  Claude pane: $claude_pane (updated tmp/claude-pane-id)"
      else
        echo "  Warning: Left pane (index 0) not found" >&2
      fi
      if [ -n "$codex_pane" ]; then
        echo "$codex_pane" > "$(codex_tmp_path codex-pane-id)"
        echo "  Codex pane: $codex_pane (updated tmp/codex-pane-id)"
      else
        echo "  Warning: Right pane (index 1) not found" >&2
      fi
    fi

    if [ "$do_attach" = true ]; then
      echo "Attaching to existing session..."
      tmux -S "$socket" attach-session -t "$session_name"
    fi
    return 0
  fi

  echo "Creating new collab session..."
  echo "  Socket: $socket"
  echo "  Session: $session_name"

  # Create new session (detached)
  tmux -S "$socket" new-session -d -s "$session_name" -n main

  # Split window horizontally to create right pane (for Codex)
  tmux -S "$socket" split-window -t "$session_name" -h

  # Get pane IDs using pane_index for reliable left/right detection
  # pane_index 0 = left (Claude), pane_index 1 = right (Codex)
  local claude_pane codex_pane
  claude_pane=$(tmux -S "$socket" list-panes -t "$session_name" -F '#{pane_index} #{pane_id}' | awk '$1==0 {print $2}')
  codex_pane=$(tmux -S "$socket" list-panes -t "$session_name" -F '#{pane_index} #{pane_id}' | awk '$1==1 {print $2}')

  # Verify panes were created successfully
  if [ -z "$claude_pane" ] || [ -z "$codex_pane" ]; then
    echo "Error: Failed to create expected 2-pane layout" >&2
    echo "Available panes:"
    tmux -S "$socket" list-panes -t "$session_name" -F '  #{pane_index}: #{pane_id}'
    return 1
  fi

  echo "$claude_pane" > "$(codex_tmp_path claude-pane-id)"
  echo "  Claude pane: $claude_pane (saved to tmp/claude-pane-id)"
  echo "$codex_pane" > "$(codex_tmp_path codex-pane-id)"
  echo "  Codex pane: $codex_pane (saved to tmp/codex-pane-id)"

  # Start Codex in right pane if requested
  if [ "$start_codex" = true ]; then
    local codex_cmd="${CODEX_CMD:-codex -s workspace-write}"
    echo "  Starting Codex: $codex_cmd"
    tmux -S "$socket" send-keys -t "$codex_pane" "$codex_cmd" Enter
  else
    # Show instructions
    tmux -S "$socket" send-keys -t "$codex_pane" "# Run: codex -s workspace-write" Enter
  fi

  # Start Claude Code in left pane if requested
  if [ "$start_claude" = true ]; then
    local claude_cmd="${CLAUDE_CMD:-claude}"
    echo "  Starting Claude Code: $claude_cmd"
    tmux -S "$socket" send-keys -t "$claude_pane" "$claude_cmd" Enter
  else
    # Show instructions
    tmux -S "$socket" send-keys -t "$claude_pane" "# Run: claude" Enter
  fi

  # Select left pane (Claude Code)
  tmux -S "$socket" select-pane -t "$claude_pane"

  echo ""
  echo "Session created successfully!"
  echo "To attach: tmux -S $socket attach-session -t $session_name"

  # Attach if requested
  if [ "$do_attach" = true ]; then
    echo "Attaching..."
    tmux -S "$socket" attach-session -t "$session_name"
  fi

  return 0
}

# Check if collab session exists
# Usage: codex_collab_session_exists [--socket PATH] [--session NAME]
# Returns: 0 if exists, 1 if not
# Note: If --socket/--session value is missing, uses default silently
codex_collab_session_exists() {
  local socket="${CODEX_TMUX_SOCKET:-./collab.sock}"
  local session_name="collab"

  while [ $# -gt 0 ]; do
    case "$1" in
      --socket)
        # Use provided value or keep default if missing
        [ -n "${2:-}" ] && socket="$2" && shift
        shift
        ;;
      --session)
        # Use provided value or keep default if missing
        [ -n "${2:-}" ] && session_name="$2" && shift
        shift
        ;;
      *)
        shift
        ;;
    esac
  done

  tmux -S "$socket" has-session -t "$session_name" 2>/dev/null
}

# Get collab session info
# Usage: codex_collab_session_info [--socket PATH] [--session NAME]
# Outputs: JSON-like info about the session
# Note: If --socket/--session value is missing, uses default silently
codex_collab_session_info() {
  local socket="${CODEX_TMUX_SOCKET:-./collab.sock}"
  local session_name="collab"

  while [ $# -gt 0 ]; do
    case "$1" in
      --socket)
        [ -n "${2:-}" ] && socket="$2" && shift
        shift
        ;;
      --session)
        [ -n "${2:-}" ] && session_name="$2" && shift
        shift
        ;;
      *)
        shift
        ;;
    esac
  done

  if ! tmux -S "$socket" has-session -t "$session_name" 2>/dev/null; then
    echo "Session '$session_name' does not exist"
    return 1
  fi

  echo "Session: $session_name"
  echo "Socket: $socket"
  echo "Panes:"
  tmux -S "$socket" list-panes -t "$session_name" -F '  #{pane_id}: #{pane_current_command} (#{pane_width}x#{pane_height})'

  # Show saved pane IDs if available
  local claude_pane_file codex_pane_file
  claude_pane_file=$(codex_tmp_path claude-pane-id)
  codex_pane_file=$(codex_tmp_path codex-pane-id)
  if [ -f "$claude_pane_file" ]; then
    echo "Claude pane (saved): $(cat "$claude_pane_file")"
  fi
  if [ -f "$codex_pane_file" ]; then
    echo "Codex pane (saved): $(cat "$codex_pane_file")"
  fi
}

# Kill collab session
# Usage: codex_collab_session_kill [--socket PATH] [--session NAME]
# Note: If --socket/--session value is missing, uses default silently
codex_collab_session_kill() {
  local socket="${CODEX_TMUX_SOCKET:-./collab.sock}"
  local session_name="collab"

  while [ $# -gt 0 ]; do
    case "$1" in
      --socket)
        [ -n "${2:-}" ] && socket="$2" && shift
        shift
        ;;
      --session)
        [ -n "${2:-}" ] && session_name="$2" && shift
        shift
        ;;
      *)
        shift
        ;;
    esac
  done

  if tmux -S "$socket" has-session -t "$session_name" 2>/dev/null; then
    tmux -S "$socket" kill-session -t "$session_name"
    echo "Session '$session_name' killed"
  else
    echo "Session '$session_name' does not exist"
    return 1
  fi

  # Clean up pane ID files
  rm -f "$(codex_tmp_path claude-pane-id)" "$(codex_tmp_path codex-pane-id)"
}

# ==============================================================================
# Lightweight Metadata Extraction
# ==============================================================================
#
# Functions to extract metadata from Codex responses.
# Metadata is expected in a YAML block at the end of the response:
#
#   ---
#   status: continue
#   verdict: pass
#   open_questions:
#     - question 1
#   ---
#

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

# Get a list field from metadata (simple single-line items only)
# Usage: codex_get_list "$metadata" "open_questions"
# Returns: One item per line
codex_get_list() {
  local metadata="$1"
  local field="$2"

  echo "$metadata" | awk -v field="$field" '
    $0 ~ "^" field ":" {
      in_list = 1
      next
    }
    in_list && /^  - / {
      sub(/^  - /, "")
      print
    }
    in_list && /^[a-z_]+:/ {
      # New field starts, end list
      in_list = 0
    }
  '
}

# Fallback: Try to extract verdict from natural language response
# Usage: verdict=$(codex_extract_verdict_fallback "$response")
# Looks for PASS, FAIL, CONDITIONAL in the response
codex_extract_verdict_fallback() {
  local response="$1"

  # Look for explicit verdict markers (case-insensitive)
  if echo "$response" | grep -qiE '\bPASS\b'; then
    echo "pass"
  elif echo "$response" | grep -qiE '\bFAIL\b'; then
    echo "fail"
  elif echo "$response" | grep -qiE '\bCONDITIONAL\b'; then
    echo "conditional"
  else
    echo ""
  fi
}

# Parse response and extract both body and metadata
# Usage: codex_parse_response "$response"
# Outputs: Sets global variables CODEX_RESPONSE_BODY, CODEX_RESPONSE_META
codex_parse_response() {
  local response="$1"

  # Extract metadata
  CODEX_RESPONSE_META=$(codex_extract_metadata "$response")

  # Extract body (everything before the last metadata block)
  # Remove the last --- ... --- block
  CODEX_RESPONSE_BODY=$(echo "$response" | awk '
    {
      lines[NR] = $0
    }
    /^---$/ {
      if (in_block) {
        end_line = NR
        in_block = 0
      } else {
        start_line = NR
        in_block = 1
      }
    }
    END {
      # Print everything except the last metadata block
      if (start_line && end_line && end_line > start_line) {
        for (i = 1; i < start_line; i++) {
          print lines[i]
        }
      } else {
        # No valid metadata block found, print everything
        for (i = 1; i <= NR; i++) {
          print lines[i]
        }
      }
    }
  ')

  # Export for use by caller
  export CODEX_RESPONSE_BODY
  export CODEX_RESPONSE_META
}
