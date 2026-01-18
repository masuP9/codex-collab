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

### Step 0: Handle Special Commands

Before any pane detection, check if the argument is a special command.
**Important:** Each special command MUST exit after handling to prevent fallthrough.

```bash
ARGUMENT="$ARGUMENTS"

# Helper: Cross-platform hash function (md5sum on Linux, md5 on macOS)
hash_content() {
  if command -v md5sum &>/dev/null; then
    md5sum | awk '{print $1}'
  else
    md5
  fi
}

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
    rm -f "$(pwd)/.codex-pane-id"
    echo "Detached from Codex pane (removed .codex-pane-id)"
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
if [ -z "$TMUX" ]; then
  echo "Error: Not inside a tmux session. Run 'tmux' first."
  exit 1
fi
```

### Step 2: Find Existing Codex Pane

Search for an existing Codex pane using multiple detection methods with verification:

**Method 1: Check stored pane ID file (with command verification)**
```bash
PANE_ID_FILE="$(pwd)/.codex-pane-id"
if [ -f "$PANE_ID_FILE" ]; then
  STORED_PANE_ID=$(cat "$PANE_ID_FILE")
  # Validate pane still exists AND is running codex
  PANE_INFO=$(tmux list-panes -a -F '#{pane_id} #{pane_current_command}' | grep "^${STORED_PANE_ID} ")
  if [ -n "$PANE_INFO" ]; then
    PANE_CMD=$(echo "$PANE_INFO" | awk '{print $2}')
    if echo "$PANE_CMD" | grep -qi "codex"; then
      CODEX_PANE="$STORED_PANE_ID"
      echo "Found Codex pane from stored ID: $CODEX_PANE (command: $PANE_CMD)"
    else
      echo "Warning: Stored pane $STORED_PANE_ID exists but running '$PANE_CMD', not codex"
    fi
  fi
fi
```

**Method 2: Search by pane_current_command (most reliable)**
```bash
if [ -z "$CODEX_PANE" ]; then
  # Look for pane running codex as current command
  CODEX_MATCHES=$(tmux list-panes -a -F '#{pane_id} #{pane_current_command}' | grep -i codex)
  MATCH_COUNT=$(echo "$CODEX_MATCHES" | grep -c . || echo 0)

  if [ "$MATCH_COUNT" -eq 1 ]; then
    CODEX_PANE=$(echo "$CODEX_MATCHES" | awk '{print $1}')
    echo "Found Codex pane by command: $CODEX_PANE"
  elif [ "$MATCH_COUNT" -gt 1 ]; then
    echo "Warning: Multiple Codex panes found ($MATCH_COUNT):"
    echo "$CODEX_MATCHES" | while read -r line; do echo "  $line"; done
    echo ""
    echo "Using first match. To specify a different pane:"
    echo "  1. Use '/collab-attach detach' then manually set pane ID"
    echo "  2. Or close unused Codex panes"
    CODEX_PANE=$(echo "$CODEX_MATCHES" | head -1 | awk '{print $1}')
    echo "Selected: $CODEX_PANE"
  fi
fi
```

**Method 3: Search by pane content (fallback with warning)**
```bash
if [ -z "$CODEX_PANE" ]; then
  # Search each pane for Codex CLI signature in recent output
  for pane in $(tmux list-panes -a -F '#{pane_id}'); do
    PANE_CONTENT=$(tmux capture-pane -t "$pane" -p -S -50 2>/dev/null)
    # Look for Codex CLI unique UI signature (box drawing + header)
    # Pattern: "│ >_ OpenAI Codex" - this is unique to the Codex CLI UI
    if echo "$PANE_CONTENT" | grep -q "│ >_ OpenAI Codex"; then
      CODEX_PANE="$pane"
      echo "Found Codex pane by content: $CODEX_PANE (content-based detection)"
      echo "Warning: Content-based detection is less reliable. Consider verifying the pane."
      break
    fi
  done
fi
```

**If no pane found:**
```bash
if [ -z "$CODEX_PANE" ]; then
  echo "Error: No Codex pane found."
  echo ""
  echo "To start a Codex pane:"
  echo "  tmux split-window -h 'codex'   # or just 'codex' for interactive mode"
  echo ""
  echo "Then run /collab-attach again."
  echo ""
  echo "Available panes:"
  tmux list-panes -a -F '  #{pane_id}: #{pane_current_command} (#{pane_title})'
  exit 1
fi
```

**Save pane ID for future use:**
```bash
echo "$CODEX_PANE" > "$PANE_ID_FILE"
echo "Pane ID saved to $PANE_ID_FILE"
```

### Step 3: Check Session State (for context optimization)

Determine if this is the first prompt in a session or a continuation:

```bash
SESSION_STATE_FILE="$(pwd)/.codex-session-state"
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
CAPTURE_FILE="$(pwd)/.codex-attach-capture.txt"
rm -f "$CAPTURE_FILE"

# Capture current pane content
BEFORE_CONTENT=$(tmux capture-pane -t "$CODEX_PANE" -p -S -5000)
BEFORE_HASH=$(echo "$BEFORE_CONTENT" | hash_content)
echo "Current state hash: $BEFORE_HASH"
```

### Step 4: Send Prompt to Codex Pane

Generate a unique marker and send the prompt. Use different templates for new vs continuing sessions:

```bash
PROMPT_FILE="$(pwd)/.codex-attach-prompt.txt"

# Generate unique marker using timestamp and random
MARKER_ID="$(date +%s)-$RANDOM"
END_MARKER="<<RESPONSE_END_${MARKER_ID}>>"

# Build prompt based on session state
USER_PROMPT="$ARGUMENTS"

if [ "$IS_NEW_SESSION" = true ]; then
  # New session: include full context header
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
  # Continuing session: use lightweight update format
  cat > "$PROMPT_FILE" << PROMPT_EOF
## Update (Turn $TURN_COUNT)

$USER_PROMPT
PROMPT_EOF
  echo "Using lightweight template (continuing session, turn $TURN_COUNT)"
fi

# Also write instruction for end marker (separate from prompt)
MARKER_INSTRUCTION="

When finished, output exactly: $END_MARKER"

# Read prompt content
PROMPT_CONTENT=$(cat "$PROMPT_FILE")

# Create temporary file with full prompt content
TEMP_PROMPT="/tmp/codex-prompt-$$"
echo "${PROMPT_CONTENT}${MARKER_INSTRUCTION}" > "$TEMP_PROMPT"

# Send prompt using load-buffer + paste-buffer for reliable multi-line input
# This avoids issues with special characters and long prompts in send-keys
# Note: 'Enter' is sent separately after paste for Codex interactive mode compatibility
tmux load-buffer "$TEMP_PROMPT"
tmux paste-buffer -t "$CODEX_PANE"
# Small delay to ensure paste completes before sending Enter
sleep 0.1
tmux send-keys -t "$CODEX_PANE" Enter
rm -f "$TEMP_PROMPT"

echo "Prompt sent to Codex pane: $CODEX_PANE"
echo "Completion marker: $END_MARKER"
```

### Step 5: Wait for Response

Poll for completion using the unique marker or hash-based change detection:

```bash
WAIT_TIMEOUT=180  # seconds
POLL_INTERVAL=2   # seconds
IDLE_THRESHOLD=5  # polls without change

echo "Waiting for Codex response..."

COMPLETED=false
IDLE_COUNT=0
LAST_HASH="$BEFORE_HASH"

for i in $(seq 1 $((WAIT_TIMEOUT / POLL_INTERVAL))); do
  # Capture recent pane output
  CURRENT_OUTPUT=$(tmux capture-pane -t "$CODEX_PANE" -p -S -5000)
  CURRENT_HASH=$(echo "$CURRENT_OUTPUT" | hash_content)

  # Check for completion marker (unique per request, not in original prompt)
  if echo "$CURRENT_OUTPUT" | grep -qF "$END_MARKER"; then
    echo "Codex response completed (marker found)"
    COMPLETED=true
    break
  fi

  # Hash-based idle detection
  if [ "$CURRENT_HASH" = "$LAST_HASH" ]; then
    IDLE_COUNT=$((IDLE_COUNT + 1))
    if [ "$IDLE_COUNT" -ge "$IDLE_THRESHOLD" ]; then
      # No change for threshold * poll_interval seconds
      # Check if Codex appears to be at prompt (ready for input)
      if echo "$CURRENT_OUTPUT" | tail -3 | grep -qE '^>\s*$|^codex>\s*$|^\[codex\]'; then
        echo "Codex appears idle at prompt (no marker, but ready for input)"
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
  echo "Warning: Timeout after ${WAIT_TIMEOUT}s - response may be incomplete"
  echo "You can manually check the pane or use '/collab-attach capture'"
fi
```

### Step 6: Extract Response

Extract the new output:

```bash
# Capture final output
FINAL_OUTPUT=$(tmux capture-pane -t "$CODEX_PANE" -p -S -5000)

# Save to file for reading
echo "$FINAL_OUTPUT" > "$CAPTURE_FILE"

echo "Response captured to: $CAPTURE_FILE"
```

### Step 7: Process Response

1. Read the captured output file
2. Extract the relevant response (text after the sent prompt, before end marker if present)
3. Present the response to the user
4. If the response contains a plan or review, handle accordingly

### Step 8: Cleanup

```bash
rm -f "$(pwd)/.codex-attach-prompt.txt"
# Keep .codex-pane-id for future use
# Keep .codex-attach-capture.txt for debugging
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
  CAPTURE_FILE="$(pwd)/.codex-attach-capture.txt"
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
rm -f "$(pwd)/.codex-pane-id"
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
- Pane ID is stored in `.codex-pane-id` for persistence across commands
- Captured output is saved in `.codex-attach-capture.txt`
- Special commands (`status`, `capture`, `detach`) are handled before pane detection
