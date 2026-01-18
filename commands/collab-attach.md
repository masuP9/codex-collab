---
description: Attach to an existing Codex pane for persistent collaboration
argument-hint: [prompt to send to Codex | status | capture | detach]
allowed-tools: Read, Write, Edit, Bash, AskUserQuestion
---

# Codex Attach Mode

Attach to an existing Codex pane and send prompts for persistent collaboration.

**Requirements:**
- Must be inside a tmux session (`$TMUX` must be set)
- A Codex pane must already be running (either interactively or via previous command)

## Prompt

$ARGUMENTS

## Workflow Instructions

### Step 0: Load Helpers and Handle Special Commands

Source shared helper functions and check for special commands.
**Important:** Each special command MUST exit after handling to prevent fallthrough.

```bash
# Source helpers
HELPERS="${CLAUDE_PLUGIN_ROOT:-$(pwd)}/scripts/codex-helpers.sh"
[ -f "$HELPERS" ] && source "$HELPERS"

ARGUMENT="$ARGUMENTS"

case "$ARGUMENT" in
  status)
    # Handle status command (see Special Commands section)
    # ... (pane detection + status display)
    exit 0  # IMPORTANT: Exit to prevent fallthrough
    ;;
  capture)
    # Handle capture command (see Special Commands section)
    # ... (pane detection + capture)
    exit 0  # IMPORTANT: Exit to prevent fallthrough
    ;;
  detach)
    TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
    rm -f "$TMP_DIR/codex-pane-id"
    echo "Detached from Codex pane (removed tmp/codex-pane-id)"
    exit 0  # IMPORTANT: Exit to prevent fallthrough
    ;;
  "")
    # No argument - show interactive mode help (see Interactive Mode section)
    # ... (help display)
    exit 0  # IMPORTANT: Exit to prevent fallthrough
    ;;
  *)
    # Regular prompt - continue to Step 1
    ;;
esac
```

### Step 1: Verify tmux Session

```bash
# Use helper or inline check
if type codex_check_tmux &>/dev/null; then
  codex_check_tmux || exit 1
elif [ -z "$TMUX" ]; then
  echo "Error: Not inside a tmux session. Run 'tmux' first."
  exit 1
fi
```

### Step 2: Find Existing Codex Pane

Search for an existing Codex pane using helper function or inline detection:

```bash
TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
mkdir -p "$TMP_DIR"
PANE_ID_FILE="$TMP_DIR/codex-pane-id"
CODEX_PANE=""

# Use helper function if available
if type codex_find_pane &>/dev/null; then
  CODEX_PANE=$(codex_find_pane "$PANE_ID_FILE")
else
  # Inline fallback: Check stored pane ID first
  if [ -f "$PANE_ID_FILE" ]; then
    STORED_PANE_ID=$(cat "$PANE_ID_FILE")
    PANE_INFO=$(tmux list-panes -a -F '#{pane_id} #{pane_current_command}' | grep "^${STORED_PANE_ID} ")
    if [ -n "$PANE_INFO" ]; then
      PANE_CMD=$(echo "$PANE_INFO" | awk '{print $2}')
      if echo "$PANE_CMD" | grep -qi "codex"; then
        CODEX_PANE="$STORED_PANE_ID"
        echo "Found Codex pane from stored ID: $CODEX_PANE"
      fi
    fi
  fi

  # Fallback: Search by command
  if [ -z "$CODEX_PANE" ]; then
    CODEX_MATCHES=$(tmux list-panes -a -F '#{pane_id} #{pane_current_command}' | grep -i codex)
    MATCH_COUNT=$(echo "$CODEX_MATCHES" | grep -c . || echo 0)
    if [ "$MATCH_COUNT" -ge 1 ]; then
      CODEX_PANE=$(echo "$CODEX_MATCHES" | head -1 | awk '{print $1}')
      [ "$MATCH_COUNT" -gt 1 ] && echo "Warning: Multiple Codex panes found, using $CODEX_PANE"
    fi
  fi

  # Fallback: Search by content
  if [ -z "$CODEX_PANE" ]; then
    for pane in $(tmux list-panes -a -F '#{pane_id}'); do
      PANE_CONTENT=$(tmux capture-pane -t "$pane" -p -S -50 2>/dev/null)
      if echo "$PANE_CONTENT" | grep -q "│ >_ OpenAI Codex"; then
        CODEX_PANE="$pane"
        echo "Found Codex pane by content: $CODEX_PANE"
        break
      fi
    done
  fi
fi

# Check if pane was found
if [ -z "$CODEX_PANE" ]; then
  echo "Error: No Codex pane found."
  echo ""
  echo "To start a Codex pane:"
  echo "  tmux split-window -h 'codex'"
  echo ""
  echo "Available panes:"
  tmux list-panes -a -F '  #{pane_id}: #{pane_current_command}'
  exit 1
fi

# Save pane ID for future use (if not already saved by helper)
echo "$CODEX_PANE" > "$PANE_ID_FILE"
echo "Pane ID saved to $PANE_ID_FILE"
```

### Step 3: Check Session State (for context optimization)

Determine if this is the first prompt in a session or a continuation:

```bash
SESSION_STATE_FILE="$TMP_DIR/codex-session-state"
SESSION_TIMEOUT=1800  # 30 minutes in seconds (configurable via settings)
IS_NEW_SESSION=false
TURN_COUNT=1  # Start at 1 for new sessions

# Check if jq is available (required for JSON parsing)
if ! command -v jq &>/dev/null; then
  echo "Warning: jq not found. Session state tracking disabled."
  IS_NEW_SESSION=true
else
  if [ -f "$SESSION_STATE_FILE" ]; then
    # Read existing session state
    LAST_PROMPT_TS=$(jq -r '.last_prompt_ts // 0' "$SESSION_STATE_FILE" 2>/dev/null || echo 0)
    TURN_COUNT=$(jq -r '.turn_count // 1' "$SESSION_STATE_FILE" 2>/dev/null || echo 1)
    STORED_PANE=$(jq -r '.pane_id // ""' "$SESSION_STATE_FILE" 2>/dev/null || echo "")

    CURRENT_TS=$(date +%s)
    TIME_DIFF=$((CURRENT_TS - LAST_PROMPT_TS))

    # Check if session is stale or pane changed
    if [ "$TIME_DIFF" -gt "$SESSION_TIMEOUT" ] || [ "$STORED_PANE" != "$CODEX_PANE" ]; then
      IS_NEW_SESSION=true
      TURN_COUNT=1
      echo "Session reset (timeout: ${TIME_DIFF}s > ${SESSION_TIMEOUT}s or pane changed)"
    else
      TURN_COUNT=$((TURN_COUNT + 1))
      echo "Continuing session (turn: $TURN_COUNT, last prompt: ${TIME_DIFF}s ago)"
    fi
  else
    IS_NEW_SESSION=true
    echo "New session (no state file)"
  fi

  # Update session state
  cat > "$SESSION_STATE_FILE" << EOF
{
  "last_prompt_ts": $(date +%s),
  "turn_count": $TURN_COUNT,
  "pane_id": "$CODEX_PANE"
}
EOF
fi
```

> **Note:** Session state tracking requires `jq`. If not installed, sessions are treated as new each time.

### Step 3a: Capture Current State (with hash for change detection)

Before sending the prompt, capture the current state:

```bash
CAPTURE_FILE="$TMP_DIR/codex-attach-capture.txt"
rm -f "$CAPTURE_FILE"

# Capture current pane content
BEFORE_CONTENT=$(tmux capture-pane -t "$CODEX_PANE" -p -S -5000)

# Use helper or inline fallback for hash
if type codex_hash_content &>/dev/null; then
  BEFORE_HASH=$(echo "$BEFORE_CONTENT" | codex_hash_content)
else
  BEFORE_HASH=$(echo "$BEFORE_CONTENT" | md5sum 2>/dev/null | awk '{print $1}' || md5)
fi
echo "Current state hash: $BEFORE_HASH"
```

### Step 4: Send Prompt to Codex Pane

Generate a unique marker and send the prompt. Use different templates for new vs continuing sessions:

```bash
PROMPT_FILE="$TMP_DIR/codex-attach-prompt.txt"
USER_PROMPT="$ARGUMENTS"

# Build prompt based on session state
if [ "$IS_NEW_SESSION" = true ]; then
  cat > "$PROMPT_FILE" << PROMPT_EOF
## Context (New Session)

You are collaborating with Claude Code. This is the start of a new collaboration session.

- Working directory: $(pwd)
- Session turn: 1

## Request

$USER_PROMPT
PROMPT_EOF
  echo "Using full context template (new session)"
else
  cat > "$PROMPT_FILE" << PROMPT_EOF
## Update (Turn $TURN_COUNT)

$USER_PROMPT
PROMPT_EOF
  echo "Using lightweight template (continuing session, turn $TURN_COUNT)"
fi

PROMPT_CONTENT=$(cat "$PROMPT_FILE")

# Use helper or inline fallback for sending prompt
if type codex_send_prompt &>/dev/null; then
  END_MARKER=$(codex_send_prompt "$CODEX_PANE" "$PROMPT_CONTENT")
  echo "Prompt sent to Codex pane: $CODEX_PANE"
  echo "Completion marker: $END_MARKER"
else
  # Inline fallback
  MARKER_ID="$(date +%s)-$RANDOM"
  END_MARKER="<<RESPONSE_END_${MARKER_ID}>>"
  TEMP_PROMPT="$TMP_DIR/codex-prompt-$$"
  echo "${PROMPT_CONTENT}

When finished, output exactly: ${END_MARKER}" > "$TEMP_PROMPT"
  tmux load-buffer "$TEMP_PROMPT"
  tmux paste-buffer -t "$CODEX_PANE"
  sleep 0.2
  tmux send-keys -t "$CODEX_PANE" Enter
  rm -f "$TEMP_PROMPT"
  echo "Prompt sent to Codex pane: $CODEX_PANE"
  echo "Completion marker: $END_MARKER"
fi
```

### Step 5: Wait for Response

Poll for completion using the unique marker or hash-based change detection:

```bash
# Use helper or inline fallback for completion detection
if type codex_wait_completion &>/dev/null; then
  CODEX_WAIT_TIMEOUT=180
  codex_wait_completion "$CODEX_PANE" "$END_MARKER" "$BEFORE_HASH"
else
  # Inline fallback
  WAIT_TIMEOUT=180
  POLL_INTERVAL=2
  IDLE_THRESHOLD=5
  COMPLETED=false
  IDLE_COUNT=0
  LAST_HASH="$BEFORE_HASH"

  echo "Waiting for Codex response..."
  for i in $(seq 1 $((WAIT_TIMEOUT / POLL_INTERVAL))); do
    CURRENT_OUTPUT=$(tmux capture-pane -t "$CODEX_PANE" -p -S -5000)
    CURRENT_HASH=$(echo "$CURRENT_OUTPUT" | md5sum 2>/dev/null | awk '{print $1}' || md5)

    if echo "$CURRENT_OUTPUT" | grep -qF "$END_MARKER"; then
      echo "Codex response completed (marker found)"
      COMPLETED=true
      break
    fi

    if [ "$CURRENT_HASH" = "$LAST_HASH" ]; then
      IDLE_COUNT=$((IDLE_COUNT + 1))
      if [ "$IDLE_COUNT" -ge "$IDLE_THRESHOLD" ]; then
        if echo "$CURRENT_OUTPUT" | tail -3 | grep -qE '^>\s*$|^codex>\s*$|^\[codex\]'; then
          echo "Codex appears idle at prompt"
          COMPLETED=true
          break
        fi
      fi
    else
      IDLE_COUNT=0
      LAST_HASH="$CURRENT_HASH"
    fi
    sleep $POLL_INTERVAL
  done

  if [ "$COMPLETED" = false ]; then
    echo "Warning: Timeout after ${WAIT_TIMEOUT}s - use '/collab-attach capture' to check"
  fi
fi
```

### Step 6: Extract Response

Extract the new output:

```bash
# Use helper or inline for capture
if type codex_capture_output &>/dev/null; then
  codex_capture_output "$CODEX_PANE" "$CAPTURE_FILE"
else
  tmux capture-pane -t "$CODEX_PANE" -p -S -5000 > "$CAPTURE_FILE"
fi
echo "Response captured to: $CAPTURE_FILE"
```

### Step 7: Process Response

1. Read the captured output file
2. Extract the relevant response (text after the sent prompt, before end marker if present)
3. Present the response to the user
4. If the response contains a plan or review, handle accordingly

### Step 8: Cleanup

```bash
rm -f "$TMP_DIR/codex-attach-prompt.txt"
# Keep tmp/codex-pane-id for future use
# Keep tmp/codex-attach-capture.txt for debugging
```

## Special Commands

### status
Show Codex pane status (handled at Step 0):
```bash
# First, find the pane (same detection logic as Step 2)
# Then show status

if [ -n "$CODEX_PANE" ]; then
  echo "Codex pane: $CODEX_PANE"
  echo ""
  echo "Pane info:"
  tmux list-panes -a -F '  #{pane_id}: pid=#{pane_pid} cmd=#{pane_current_command} size=#{pane_width}x#{pane_height}' | grep "^  $CODEX_PANE:"
  echo ""
  echo "Recent output (last 15 lines):"
  tmux capture-pane -t "$CODEX_PANE" -p -S -15
else
  echo "No Codex pane found. Use 'tmux split-window -h codex' to start one."
fi
```

### capture
Capture current Codex output (handled at Step 0):
```bash
# First, find the pane (same detection logic as Step 2)
# Then capture

if [ -n "$CODEX_PANE" ]; then
  TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
  mkdir -p "$TMP_DIR"
  CAPTURE_FILE="$TMP_DIR/codex-attach-capture.txt"
  tmux capture-pane -t "$CODEX_PANE" -p -S -5000 > "$CAPTURE_FILE"
  echo "Captured to: $CAPTURE_FILE"
  echo ""
  cat "$CAPTURE_FILE"
else
  echo "No Codex pane found."
fi
```

### detach
Remove stored pane ID (handled at Step 0):
```bash
TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
rm -f "$TMP_DIR/codex-pane-id"
echo "Detached from Codex pane"
```

## Interactive Mode

If no argument is provided, show help:

```bash
if [ -z "$ARGUMENT" ]; then
  echo "Codex Attach Mode"
  echo ""

  # Try to find existing pane
  # (same detection logic as Step 2)

  if [ -n "$CODEX_PANE" ]; then
    echo "Connected to Codex pane: $CODEX_PANE"
    echo ""
    echo "Recent output (last 10 lines):"
    tmux capture-pane -t "$CODEX_PANE" -p -S -10
    echo ""
  else
    echo "No Codex pane found."
    echo ""
  fi

  echo "Usage:"
  echo "  /collab-attach <prompt>  - Send a prompt to Codex"
  echo "  /collab-attach status    - Show Codex pane status"
  echo "  /collab-attach capture   - Capture current Codex output"
  echo "  /collab-attach detach    - Remove stored pane ID"
fi
```

## Error Handling

**If tmux send-keys fails:**
- Check if pane still exists: `tmux list-panes -a -F '#{pane_id}' | grep "$CODEX_PANE"`
- Report error and suggest using `detach` then re-attaching

**If Codex doesn't respond:**
- Check pane content for error messages
- Suggest manual intervention in the Codex pane

**If completion marker not found:**
- Hash-based idle detection is used as fallback
- Capture whatever output is available
- Warn user that response may be incomplete

**If wrong pane detected:**
- Use `/collab-attach detach` to clear stored pane ID
- Manually verify the correct pane
- Start Codex with explicit pane: `tmux split-window -h 'codex'`

## Security Notes

- **Pane verification**: Detection prioritizes `pane_current_command` check to ensure we're sending to a Codex process
- **Unique markers**: Each request uses a unique marker (timestamp + random) to avoid false-positive completion detection
- **No command injection**: Prompts are sent via tmux send-keys which treats content as literal text, not shell commands
- **Content-based detection warning**: When using content heuristics, a warning is shown as it's less reliable

## Notes

- This command requires an existing Codex pane (it does not create one)
- The completion marker is requested but not guaranteed to be output by Codex
- Hash-based idle detection provides reliable fallback for completion
- Pane ID is stored in `tmp/codex-pane-id` for persistence across commands
- Captured output is saved in `tmp/codex-attach-capture.txt`
- Special commands (`status`, `capture`, `detach`) are handled before pane detection
