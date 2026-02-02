---
name: collab-codex
description: Start a collaborative task with Codex (Codex plans/reviews, Claude implements)
argument-hint: [task description]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, AskUserQuestion
---

# Codex Collaboration Workflow

Execute a collaborative workflow between Claude Code and Codex CLI.

**Launch modes** (`launch.mode` setting):
- **tmux**: 現在のペインを水平分割し、右側でCodexを実行。フォーカスを奪わない。
- **wt**: Windows Terminalの新しいペインで実行。フォーカスを奪う可能性あり。
- **inline**: 現在のターミナルで実行（完了までブロック）。
- **auto** (default): tmuxセッション内 → tmux、それ以外 → wt → inline。

## Task

$ARGUMENTS

## Workflow Instructions

### Step 0: Load Helper Functions

Source shared helper functions at the beginning of any bash block. **Always set `CODEX_SKILL_CONTEXT=1`** to indicate skill context for the PreToolUse hook:

```bash
# Mark skill context for PreToolUse hook detection
export CODEX_SKILL_CONTEXT=1

# Source helpers (assumes running from plugin root or project root)
HELPERS="${CLAUDE_PLUGIN_ROOT:-$(pwd)}/scripts/codex-helpers.sh"
if [ -f "$HELPERS" ]; then
  source "$HELPERS"
fi
```

> **Note:** If helpers are not available, the bash blocks include inline fallback definitions where necessary.
> **Important:** The `CODEX_SKILL_CONTEXT=1` export is required for the PreToolUse hook to recognize this as skill context and allow Bash execution without blocking.

### Step 1: Load Settings

Check for project-specific settings:
- Read `.claude/codex-collab.local.md` if it exists
- Extract YAML frontmatter for: model, sandbox, codex, exchange, review settings
- Apply settings priority: command args > project settings > defaults

**Default settings:**
- model: (Codex default)
- sandbox: read-only
- language: en (Codex response language)
- **Timeout** (codex.*):
  - codex.wait_timeout: 180 (seconds, max 600)
- **Launch mode** (launch.*):
  - launch.mode: auto (options: auto, wt, tmux, inline)
  - launch.prefer_attached: true (use existing attached Codex pane if available)
- **Planning exchange** (exchange.*):
  - exchange.enabled: true
  - exchange.max_iterations: 3
  - exchange.user_confirm: on_important
  - exchange.history_mode: summarize
- **Review iteration** (review.*):
  - review.enabled: true
  - review.max_iterations: 5
  - review.user_confirm: never

**Language setting:**
When `language` is set to a non-English value (e.g., `ja`), all Codex prompts will be prefixed with a language directive:
```
**{language}で回答してください。**

[Original prompt content]
```

This ensures Codex responds in the specified language regardless of the prompt template language.

### Step 2: Analyze Task

**Before starting, create a task to track progress:**

Use TaskCreate:
- subject: "Analyze task and gather context"
- description: "Load settings, identify affected files, prepare context for Codex"
- activeForm: "Analyzing task"

Then use TaskUpdate to set status to `in_progress`.

**Perform analysis:**
1. Identify the core objective from the task description
2. List potentially affected files
3. Gather relevant context by reading key files
4. Prepare a summary for Codex

### Step 3: Request Plan from Codex

**Task transition:**
1. Mark "Analyze task and gather context" as `completed`
2. Use TaskCreate:
   - subject: "Get implementation plan from Codex"
   - description: "Request plan, wait for completion, process response"
   - activeForm: "Getting plan from Codex"
3. Use TaskUpdate to set status to `in_progress`

Launch Codex based on `launch.mode` setting. Output is saved to project directory for sharing between sessions.

**1. Prepare files (always run first):**
```bash
# Ensure tmp directory exists and set output file paths
TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
mkdir -p "$TMP_DIR"
CODEX_OUTPUT="$TMP_DIR/codex-plan-output.md"
CODEX_PROMPT="$TMP_DIR/codex-plan-prompt.txt"
rm -f "$CODEX_OUTPUT"

# Source helpers for language directive
HELPERS="${CLAUDE_PLUGIN_ROOT:-$(pwd)}/scripts/codex-helpers.sh"
[ -f "$HELPERS" ] && source "$HELPERS"

# Get language setting from config (default: en)
# LANGUAGE variable should be read from settings file in Step 1
LANGUAGE="${LANGUAGE:-en}"

# Get language directive (empty for English)
LANG_DIRECTIVE=""
if type codex_get_language_directive &>/dev/null; then
  LANG_DIRECTIVE=$(codex_get_language_directive "$LANGUAGE")
else
  # Inline fallback
  if [ "$LANGUAGE" != "en" ] && [ -n "$LANGUAGE" ]; then
    if [ "$LANGUAGE" = "ja" ]; then
      LANG_DIRECTIVE="**日本語で回答してください。途中の説明や思考プロセスも日本語で記述してください。**

"
    else
      LANG_DIRECTIVE="**${LANGUAGE}で回答してください。途中の説明や思考プロセスも${LANGUAGE}で記述してください。**

"
    fi
  fi
fi

# Write prompt to file (with optional language directive prefix)
cat > "$CODEX_PROMPT" << EOF
${LANG_DIRECTIVE}You are collaborating with Claude Code. Your role is to create a detailed implementation plan.

**IMPORTANT**: If you reference any files, always re-read them from disk even if you have read them before in this session. Ignore any cached content from earlier in this conversation.

## Task
[Task description]

## Context
[Relevant code context]

## Required Output

### 1. Files to Modify
List each file with type of change (create/modify/delete)

### 2. Implementation Steps
Numbered steps in execution order

### 3. Risk Assessment
Potential issues and edge cases

### 4. Test Considerations
What should be tested

## Response Format

At the end of your response, include a metadata block:

```
---
status: continue or stop
open_questions:  # if any clarification needed
  - question 1
decisions:  # key decisions made
  - decision 1
---
```

Use \`status: continue\` if you have questions, \`status: stop\` if the plan is complete.

Provide your plan now.
EOF
```

**2. Get or create Codex pane (tmux mode):**

In tmux mode, use the unified `codex_get_or_create_pane` function which:
1. First checks for an existing Codex pane (stored ID or auto-detect)
2. If not found, launches a new interactive Codex instance
3. The pane persists after each task (no auto-close)
4. Saves the pane ID for future reuse

```bash
# Source helpers
HELPERS="${CLAUDE_PLUGIN_ROOT:-$(pwd)}/scripts/codex-helpers.sh"
[ -f "$HELPERS" ] && source "$HELPERS"

TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
mkdir -p "$TMP_DIR"
PANE_ID_FILE="$TMP_DIR/codex-pane-id"
SANDBOX="${SANDBOX_SETTING:-read-only}"

# Determine launch mode
LAUNCH_MODE="inline"
if [ -n "$TMUX" ]; then
  LAUNCH_MODE="tmux"
elif command -v wt.exe &>/dev/null; then
  LAUNCH_MODE="wt"
fi
echo "Using launch mode: $LAUNCH_MODE"

# For tmux mode: get or create persistent Codex pane
CODEX_PANE=""
if [ "$LAUNCH_MODE" = "tmux" ]; then
  if type codex_get_or_create_pane &>/dev/null; then
    CODEX_PANE=$(codex_get_or_create_pane "$SANDBOX" "$PANE_ID_FILE")
  else
    # Inline fallback: check for existing pane first
    if [ -f "$PANE_ID_FILE" ]; then
      STORED_PANE=$(cat "$PANE_ID_FILE")
      # Verify pane exists, belongs to current session, and is running Codex
      CURRENT_SESSION=$(tmux display-message -p '#{session_id}' 2>/dev/null)
      PANE_SESSION=$(tmux display-message -t "$STORED_PANE" -p '#{session_id}' 2>/dev/null)
      PANE_CMD=$(tmux display-message -t "$STORED_PANE" -p '#{pane_current_command}' 2>/dev/null)
      if [ "$PANE_SESSION" = "$CURRENT_SESSION" ] && { [ "$PANE_CMD" = "codex" ] || [ "$PANE_CMD" = "node" ]; }; then
        CODEX_PANE="$STORED_PANE"
        echo "Found existing Codex pane: $CODEX_PANE"
      fi
    fi

    # If no existing pane, launch new one
    if [ -z "$CODEX_PANE" ]; then
      echo "Launching new Codex pane..."
      ORIGINAL_PANE=$(tmux display-message -p '#{pane_id}')
      # Use -P -F to directly capture the new pane ID (more reliable than list-panes filtering)
      CODEX_PANE=$(tmux split-window -h -d -c "$(pwd)" -P -F '#{pane_id}' "codex -s $SANDBOX")
      sleep 2  # Wait for Codex to initialize
      # Only save pane ID if split succeeded (non-empty)
      if [ -n "$CODEX_PANE" ]; then
        echo "$CODEX_PANE" > "$PANE_ID_FILE"
        tmux select-pane -t "$ORIGINAL_PANE"
        echo "Launched new Codex pane: $CODEX_PANE"
      fi
    fi
  fi

  if [ -z "$CODEX_PANE" ]; then
    echo "Error: Failed to get or create Codex pane"
    exit 1
  fi
fi
```

> **Key Change**: Instead of launching `codex exec` (which exits after completion), we now launch `codex` in interactive mode. The pane persists and can be reused for subsequent prompts.

**3. Send prompt and receive response (tmux mode - file-based, recommended):**

For tmux mode, use the file-based response protocol which writes responses to a file instead of capturing from the pane. This avoids truncation issues with long responses.

```bash
# Source helpers
HELPERS="${CLAUDE_PLUGIN_ROOT:-$(pwd)}/scripts/codex-helpers.sh"
[ -f "$HELPERS" ] && source "$HELPERS"

# CODEX_PANE is set from step 2
# CODEX_PROMPT file was prepared in Step 3.1
TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
WAIT_TIMEOUT="${CODEX_WAIT_TIMEOUT:-180}"

# Use file-based response workflow if available (recommended)
PROMPT_SENT=false

if type codex_file_response_workflow &>/dev/null; then
  echo "Using file-based response protocol..."

  # This function handles:
  # 1. Generate unique output file
  # 2. Add file output instructions to prompt
  # 3. Send prompt to Codex
  # 4. Wait for completion marker
  # 5. Read response from file
  RESPONSE=$(codex_file_response_workflow "$CODEX_PANE" "$CODEX_PROMPT" "$WAIT_TIMEOUT")
  WORKFLOW_RESULT=$?
  PROMPT_SENT=true  # Prompt was sent regardless of success/failure

  if [ $WORKFLOW_RESULT -eq 0 ]; then
    # Save response to output file for Step 5
    echo "$RESPONSE" > "$TMP_DIR/codex-plan-output.md"
    echo "Codex response received and saved"
  else
    echo "Warning: File-based workflow returned code $WORKFLOW_RESULT"
    echo "Prompt was already sent. Falling back to capture-pane for response retrieval."
    # Fall through to legacy capture (but NOT re-send prompt)
    USE_LEGACY_CAPTURE=true
  fi
else
  echo "File-based workflow not available, using legacy method"
  USE_LEGACY=true
fi

# Legacy fallback: only used when file-based workflow is NOT available
if [ "${USE_LEGACY:-}" = "true" ]; then
  # Capture state before sending
  BEFORE_CONTENT=$(tmux capture-pane -t "$CODEX_PANE" -p -S -5000)
  if type codex_hash_content &>/dev/null; then
    BEFORE_HASH=$(echo "$BEFORE_CONTENT" | codex_hash_content)
  else
    BEFORE_HASH=$(echo "$BEFORE_CONTENT" | md5sum 2>/dev/null | awk '{print $1}')
  fi

  # Send prompt using chunked method (handles long prompts)
  if type codex_send_prompt_chunked &>/dev/null; then
    END_MARKER=$(codex_send_prompt_chunked "$CODEX_PANE" "$(cat "$CODEX_PROMPT")")
  else
    # Inline fallback
    MARKER_ID="$(date +%s)-$RANDOM"
    END_MARKER="<<RESPONSE_END_${MARKER_ID}>>"
    PROMPT_CONTENT=$(cat "$CODEX_PROMPT")
    FULL_PROMPT="${PROMPT_CONTENT}

When finished, output exactly: ${END_MARKER}"

    tmux send-keys -t "$CODEX_PANE" C-u
    sleep 0.1
    TEMP_FILE="$TMP_DIR/codex-prompt-$$"
    echo "$FULL_PROMPT" > "$TEMP_FILE"
    tmux load-buffer "$TEMP_FILE"
    tmux paste-buffer -t "$CODEX_PANE"
    sleep 0.5
    tmux send-keys -t "$CODEX_PANE" Enter
    rm -f "$TEMP_FILE"
  fi

  echo "Prompt sent to Codex pane: $CODEX_PANE"
  echo "Completion marker: $END_MARKER"
  # Note: Wait for completion in Step 4
fi
```

> **Note:** The file-based protocol instructs Codex to write its response to a unique file (e.g., `tmp/codex-response-20260202-153045-8f3c2a.md`) and output only a completion marker to stdout. This avoids capture-pane truncation issues for long responses.

**4. Launch Codex (wt/inline mode fallback):**

For non-tmux environments, fall back to the original `codex exec` approach:

**wt mode** (Windows Terminal - may steal focus):
```bash
SANDBOX="${SANDBOX_SETTING:-read-only}"
# Note: using ; instead of && so marker is written even on Codex failure
wt.exe -w -1 -d "$(pwd)" -p Ubuntu wsl.exe zsh -i -l -c "cat \"$CODEX_PROMPT\" | codex exec -s \"$SANDBOX\" - 2>&1 | tee \"$CODEX_OUTPUT\"; echo '=== CODEX_DONE ===' >> \"$CODEX_OUTPUT\""
```

**inline mode** (fallback - blocks terminal):
```bash
SANDBOX="${SANDBOX_SETTING:-read-only}"
# Note: using ; instead of && so marker is written even on Codex failure
cat "$CODEX_PROMPT" | codex exec -s "$SANDBOX" - 2>&1 | tee "$CODEX_OUTPUT"; echo '=== CODEX_DONE ===' >> "$CODEX_OUTPUT"
```

**Legacy tmux mode** (codex exec - use only when pane persistence is not needed):
```bash
# Run Codex in a new pane (split horizontally) with signal-based completion
PROMPT="$CODEX_PROMPT"
OUTPUT="$CODEX_OUTPUT"
SANDBOX="${SANDBOX_SETTING:-read-only}"
# Unique signal: PID + timestamp + random suffix to avoid collisions
SIGNAL="codex-plan-$$-$(date +%s)-$RANDOM"

# Capture original pane ID to ensure focus returns after split
ORIGINAL_PANE=$(tmux display-message -p '#{pane_id}')

# Split current window horizontally and run Codex in the new pane
# Signal is sent even on failure (finally-style)
# NOTE: This pane closes after codex exec completes
tmux split-window -h -d \
  "cd \"$(pwd)\"; \
   cat \"$PROMPT\" | codex exec -s \"$SANDBOX\" - 2>&1 | tee \"$OUTPUT\"; \
   echo '=== CODEX_DONE ===' >> \"$OUTPUT\"; \
   tmux wait-for -S \"$SIGNAL\""

# Ensure focus returns to original pane (safety net for -d flag inconsistencies)
tmux select-pane -t "$ORIGINAL_PANE"

echo "Codex running in a new pane (right side)"
echo "Signal: $SIGNAL"
```

**wt mode** (Windows Terminal - may steal focus):
```bash
SANDBOX="${SANDBOX_SETTING:-read-only}"
# Note: using ; instead of && so marker is written even on Codex failure
wt.exe -w -1 -d "$(pwd)" -p Ubuntu wsl.exe zsh -i -l -c "cat \"$CODEX_PROMPT\" | codex exec -s \"$SANDBOX\" - 2>&1 | tee \"$CODEX_OUTPUT\"; echo '=== CODEX_DONE ===' >> \"$CODEX_OUTPUT\""
```

**inline mode** (fallback - blocks terminal):
```bash
SANDBOX="${SANDBOX_SETTING:-read-only}"
# Note: using ; instead of && so marker is written even on Codex failure
cat "$CODEX_PROMPT" | codex exec -s "$SANDBOX" - 2>&1 | tee "$CODEX_OUTPUT"; echo '=== CODEX_DONE ===' >> "$CODEX_OUTPUT"
```

**Options to include based on settings:**
- `-m, --model <model>` - Specify model (e.g., o4-mini, o3) from `model` setting
- `-s, --sandbox <mode>` - read-only | workspace-write | danger-full-access from `sandbox` setting

### Step 3-Attached: Send Prompt to Attached Pane

If an attached Codex pane was found in Step 3.0, use this flow instead of launching a new instance:

**1. Prepare prompt and capture state:**
```bash
# Source helpers
HELPERS="${CLAUDE_PLUGIN_ROOT:-$(pwd)}/scripts/codex-helpers.sh"
[ -f "$HELPERS" ] && source "$HELPERS"

TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
mkdir -p "$TMP_DIR"
CAPTURE_FILE="$TMP_DIR/codex-attach-capture.txt"
BEFORE_CONTENT=$(tmux capture-pane -t "$ATTACHED_PANE" -p -S -5000)

# Use helper or inline fallback for hash
if type codex_hash_content &>/dev/null; then
  BEFORE_HASH=$(echo "$BEFORE_CONTENT" | codex_hash_content)
else
  BEFORE_HASH=$(echo "$BEFORE_CONTENT" | md5sum 2>/dev/null | awk '{print $1}' || md5)
fi
```

**2. Send prompt using file-based method (recommended for long prompts):**
```bash
# Source helpers (if not already)
HELPERS="${CLAUDE_PLUGIN_ROOT:-$(pwd)}/scripts/codex-helpers.sh"
[ -f "$HELPERS" ] && source "$HELPERS"

# CODEX_PROMPT file was prepared in Step 3.1

# Use file-based prompt sending (avoids paste-buffer issues with long prompts)
if type codex_send_prompt_file &>/dev/null; then
  END_MARKER=$(codex_send_prompt_file "$ATTACHED_PANE" "$CODEX_PROMPT")
  echo "Prompt sent to attached Codex pane: $ATTACHED_PANE"
  echo "Completion marker: $END_MARKER"
else
  # Inline fallback: Send short reference prompt instead of full content
  MARKER_ID="$(date +%s)-$RANDOM"
  END_MARKER="<<RESPONSE_END_${MARKER_ID}>>"

  # Clear any existing input first
  tmux send-keys -t "$ATTACHED_PANE" C-u
  sleep 0.1

  # Create short reference prompt
  TEMP_PROMPT="$TMP_DIR/codex-prompt-$$"
  cat > "$TEMP_PROMPT" << EOF
Please read the instructions in ${CODEX_PROMPT} and follow them.

---
IMPORTANT: After completing your response, output this exact marker on its own line:
${END_MARKER}
EOF
  tmux load-buffer "$TEMP_PROMPT"
  tmux paste-buffer -t "$ATTACHED_PANE"
  sleep 0.5
  tmux send-keys -t "$ATTACHED_PANE" Enter
  rm -f "$TEMP_PROMPT"
  echo "Prompt sent to attached Codex pane: $ATTACHED_PANE"
  echo "Completion marker: $END_MARKER"
fi
```

> **Note:** File-based prompt sending references the instruction file by path instead of pasting the full content. This avoids paste-buffer corruption issues with long prompts.

**3. Wait for completion (marker + idle detection):**
```bash
# Source helpers (if not already)
HELPERS="${CLAUDE_PLUGIN_ROOT:-$(pwd)}/scripts/codex-helpers.sh"
[ -f "$HELPERS" ] && source "$HELPERS"

# Use helper or inline fallback for completion detection
if type codex_wait_completion &>/dev/null; then
  CODEX_WAIT_TIMEOUT="${WAIT_TIMEOUT:-180}"
  codex_wait_completion "$ATTACHED_PANE" "$END_MARKER" "$BEFORE_HASH"
else
  # Inline fallback
  WAIT_TIMEOUT="${WAIT_TIMEOUT:-180}"
  POLL_INTERVAL=2
  IDLE_THRESHOLD=5
  COMPLETED=false
  IDLE_COUNT=0
  LAST_HASH="$BEFORE_HASH"

  for i in $(seq 1 $((WAIT_TIMEOUT / POLL_INTERVAL))); do
    CURRENT_OUTPUT=$(tmux capture-pane -t "$ATTACHED_PANE" -p -S -5000)
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
          echo "Codex appears idle (marker not found, using idle detection)"
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
  [ "$COMPLETED" = false ] && echo "Warning: Timeout - use '/collab-attach capture' to check output"
fi
```

**4. Capture output to file:**
```bash
# Source helpers (if not already)
HELPERS="${CLAUDE_PLUGIN_ROOT:-$(pwd)}/scripts/codex-helpers.sh"
[ -f "$HELPERS" ] && source "$HELPERS"

if type codex_capture_output &>/dev/null; then
  codex_capture_output "$ATTACHED_PANE" "$CAPTURE_FILE"
else
  tmux capture-pane -t "$ATTACHED_PANE" -p -S -5000 > "$CAPTURE_FILE"
fi
# Also save to CODEX_OUTPUT for compatibility with Step 5
cp "$CAPTURE_FILE" "$CODEX_OUTPUT"
```

> **Note:** When using attached mode, the output may contain previous conversation context. Extract the relevant response (after your prompt, before the marker) when processing.

**→ Continue to Step 5 (Read and Process Response)**

### Step 4: Wait for Codex Completion

Wait for Codex to complete. Method depends on launch mode:

> **Note:** If you used the **file-based response protocol** in Step 3 (i.e., `codex_file_response_workflow`) and it succeeded, the response is already received and saved. **Skip this step** and proceed to Step 5.
>
> If the file-based workflow **failed after sending** (USE_LEGACY_CAPTURE=true), this step will wait for completion and capture via pane (no re-send).

> **Important:** Set the Bash tool's `timeout` parameter to `min(wait_timeout + 60, 600) * 1000` milliseconds. Example: for 180s wait, use `timeout: 240000`. Max: 600000ms (10 minutes).

**tmux mode with persistent pane** (capture-pane based):

Use this if the file-based workflow was not available (USE_LEGACY) or failed after sending (USE_LEGACY_CAPTURE):

```bash
# Source helpers
HELPERS="${CLAUDE_PLUGIN_ROOT:-$(pwd)}/scripts/codex-helpers.sh"
[ -f "$HELPERS" ] && source "$HELPERS"

TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"

# Skip if file-based workflow already completed successfully
if [ -f "$TMP_DIR/codex-plan-output.md" ] && [ -s "$TMP_DIR/codex-plan-output.md" ]; then
  echo "Response already received via file-based workflow, skipping wait"
else
  # Need to wait and capture via pane
  # This handles both USE_LEGACY (prompt sent via chunked) and USE_LEGACY_CAPTURE (prompt sent via file-based but failed to get response)

  # CODEX_PANE from Step 3
  # END_MARKER and BEFORE_HASH from Step 3 (only set if USE_LEGACY)
  WAIT_TIMEOUT="${WAIT_TIMEOUT:-180}"

  # Wait for idle or marker (works for both cases)
  if type codex_wait_completion &>/dev/null; then
    CODEX_WAIT_TIMEOUT="$WAIT_TIMEOUT"
    # If END_MARKER is not set (USE_LEGACY_CAPTURE case), use empty marker - will rely on idle detection
    codex_wait_completion "$CODEX_PANE" "${END_MARKER:-}" "${BEFORE_HASH:-}"
  else
    # Inline fallback: poll for idle
    echo "Waiting for Codex to complete..."
    COMPLETED=false
    IDLE_COUNT=0
    LAST_HASH=""
    for i in $(seq 1 $WAIT_TIMEOUT); do
      CURRENT_OUTPUT=$(tmux capture-pane -t "$CODEX_PANE" -p -S -5000)
      CURRENT_HASH=$(echo "$CURRENT_OUTPUT" | md5sum 2>/dev/null | awk '{print $1}')

      # Check for marker if set
      if [ -n "${END_MARKER:-}" ] && echo "$CURRENT_OUTPUT" | grep -qF "$END_MARKER"; then
        echo "Codex response completed (marker found)"
        COMPLETED=true
        break
      fi

      # Idle detection
      if [ "$CURRENT_HASH" = "$LAST_HASH" ]; then
        IDLE_COUNT=$((IDLE_COUNT + 1))
        if [ "$IDLE_COUNT" -ge 5 ]; then
          if echo "$CURRENT_OUTPUT" | tail -5 | grep -qE '^\s*›|^>'; then
            echo "Codex appears idle"
            COMPLETED=true
            break
          fi
        fi
      else
        IDLE_COUNT=0
        LAST_HASH="$CURRENT_HASH"
      fi
      sleep 1
    done
    [ "$COMPLETED" = false ] && echo "Warning: Timeout after ${WAIT_TIMEOUT}s"
  fi

  # Capture output to file for Step 5
  tmux capture-pane -t "$CODEX_PANE" -p -S -5000 > "$TMP_DIR/codex-plan-output.md"
fi
```

**Legacy tmux mode with codex exec** (signal-based, instant detection):
```bash
# WAIT_TIMEOUT from settings (default: 180 seconds)
# SIGNAL from Step 3 (legacy mode)
# Note: Requires GNU coreutils `timeout` command. On macOS, install with `brew install coreutils` (provides `gtimeout`).
echo "Waiting for Codex..."
if timeout "${WAIT_TIMEOUT}s" tmux wait-for "$SIGNAL"; then
  echo "Codex completed"
else
  echo "Timeout after ${WAIT_TIMEOUT}s - check tmux pane or output file"
fi
```

**wt/inline mode** (file polling):
```bash
# WAIT_TIMEOUT from settings (default: 180 seconds)
echo "Waiting for Codex..."
COMPLETED=false
for i in $(seq 1 $WAIT_TIMEOUT); do
  if grep -q "=== CODEX_DONE ===" "$CODEX_OUTPUT" 2>/dev/null; then
    echo "Codex completed after ${i}s"
    COMPLETED=true
    break
  fi
  sleep 1
done

# Handle timeout
if [ "$COMPLETED" = false ]; then
  echo "Timeout after ${WAIT_TIMEOUT}s - checking Codex status..."
fi
```

**If timeout occurs:**
1. Check if Codex is still running in the tmux pane or other terminal
2. If still running → Re-run wait with extended timeout
3. If completed but marker missing → Read partial output and report error
4. If failed → Report error and offer to retry

### Step 5: Read and Process Response

**Task transition:**
1. Mark "Get implementation plan from Codex" as `completed`
2. Use TaskCreate:
   - subject: "Review and approve plan"
   - description: "Validate plan completeness, present to user for approval"
   - activeForm: "Reviewing plan"
3. Use TaskUpdate to set status to `in_progress`

Once completion is detected:

1. Read the output file: `cat "$CODEX_OUTPUT"`
2. Parse the YAML response from Codex
3. Check `next_action` field (evaluated first, takes precedence):
   - If `next_action: continue` or `type: action_request` → Go to Step 5a (Discussion Loop)
   - If `next_action: stop` → Continue to Step 6
   - If `next_action` is missing → Default to `stop` for task_card/review, `continue` for action_request
4. Validate for completeness:
   - [ ] Files to modify are clearly listed
   - [ ] Steps are specific and actionable
   - [ ] Risks are identified

Present the plan to the user and wait for confirmation before implementing.

### Step 5a: Multi-turn Exchange Loop (Optional)

If Codex requests clarification or wants to continue the exchange:

**0. Check if exchange is enabled:**
- If `exchange.enabled: false` → Skip this step, proceed to Step 6

**1. Track exchange state:**
- Increment round counter
- Check if round < exchange.max_iterations (default: 3)

**2. Prepare follow-up prompt with history:**
```
## Conversation History

### Previous Rounds Summary (if round > 2)
[Summarize key decisions, unresolved questions, constraints]

### Round {N-1}
Claude: [Your previous message]
Codex: [Codex's response]

### Round {N}
Claude: [Your current response to Codex's question/request]

## Continue Discussion

[Your response addressing Codex's question or providing requested information]

Please respond with next_action: stop when exchange is complete.
```

**3. Send follow-up to Codex:**
- Launch Codex with updated prompt
- Wait for completion
- Return to Step 5

**4. User confirmation (based on exchange.user_confirm setting):**
- `never`: Fully automatic exchange
- `always`: Confirm each round
- `on_important` (default): Confirm only for major decisions

**5. Force stop conditions:**
- round >= exchange.max_iterations → Summarize and proceed
- Repeated same question → Ask user for direction

### Step 6: Implement

**Task transition:**
1. Mark "Review and approve plan" as `completed`
2. Use TaskCreate:
   - subject: "Implement changes"
   - description: "Execute plan step by step, track modifications"
   - activeForm: "Implementing changes"
3. Use TaskUpdate to set status to `in_progress`

Execute the plan step by step:
1. Make changes as specified
2. Track all modifications
3. Prepare diff summary for review

### Step 7: Request Review from Codex (New Pane)

**Task transition:**
1. Mark "Implement changes" as `completed`
2. Use TaskCreate:
   - subject: "Request review from Codex"
   - description: "Stage changes, request review, process feedback"
   - activeForm: "Getting review from Codex"
3. Use TaskUpdate to set status to `in_progress`

Launch another Codex session for review:

**0. Stage changes for Codex visibility (important!):**
```bash
git add -A
```
> **Why?** Staging ensures all changes are visible to Codex regardless of its file discovery method. Some tools use `git ls-files` (tracked files only) or respect `.gitignore`. Staging guarantees consistency.
> This is staging only, not a commit. Run `git reset` after review to unstage if needed.
>
> **Note:** Temporary files are stored in `./tmp/` directory which is excluded by `.gitignore`, so they won't be included in the review.

**1. Prepare files:**
```bash
TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
mkdir -p "$TMP_DIR"
CODEX_REVIEW="$TMP_DIR/codex-review-output.md"
REVIEW_PROMPT="$TMP_DIR/codex-review-prompt.txt"
rm -f "$CODEX_REVIEW"

# Source helpers for language directive
HELPERS="${CLAUDE_PLUGIN_ROOT:-$(pwd)}/scripts/codex-helpers.sh"
[ -f "$HELPERS" ] && source "$HELPERS"

# Get language setting from config (default: en)
LANGUAGE="${LANGUAGE:-en}"

# Get language directive (empty for English)
LANG_DIRECTIVE=""
if type codex_get_language_directive &>/dev/null; then
  LANG_DIRECTIVE=$(codex_get_language_directive "$LANGUAGE")
else
  # Inline fallback
  if [ "$LANGUAGE" != "en" ] && [ -n "$LANGUAGE" ]; then
    if [ "$LANGUAGE" = "ja" ]; then
      LANG_DIRECTIVE="**日本語で回答してください。途中の説明や思考プロセスも日本語で記述してください。**

"
    else
      LANG_DIRECTIVE="**${LANGUAGE}で回答してください。途中の説明や思考プロセスも${LANGUAGE}で記述してください。**

"
    fi
  fi
fi

cat > "$REVIEW_PROMPT" << EOF
${LANG_DIRECTIVE}Review the implementation described below.

**IMPORTANT**: If you reference any files, always re-read them from disk even if you have read them before in this session. Ignore any cached content from earlier in this conversation.

## Original Plan
[Plan from Step 3]

## Changes Made
[Diff summary]

## Review Request

### 1. Alignment Check
Does implementation match the plan?

### 2. Code Quality
Rate readability and maintainability

### 3. Bugs and Issues
List any problems found (severity, location, suggestion)

### 4. Security Check
Any vulnerabilities?

### 5. Verdict
- PASS: No critical issues
- CONDITIONAL: Acceptable with improvements
- FAIL: Critical issues found

## Response Format

At the end of your response, include a metadata block:

```
---
status: stop
verdict: pass / conditional / fail
findings:  # if any issues found
  - severity: low / medium / high
    message: description of issue
---
```

Provide your review now.
EOF
```

> **Note:** The language directive (if configured) is automatically prepended to ensure Codex responds in the specified language.

**2. Send review request and receive response (tmux mode - file-based, recommended):**

Reuse the existing Codex pane from Step 3 and use file-based response protocol:

```bash
# Source helpers
HELPERS="${CLAUDE_PLUGIN_ROOT:-$(pwd)}/scripts/codex-helpers.sh"
[ -f "$HELPERS" ] && source "$HELPERS"

# Get existing Codex pane (should exist from Step 3)
TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
PANE_ID_FILE="$TMP_DIR/codex-pane-id"
WAIT_TIMEOUT="${CODEX_WAIT_TIMEOUT:-180}"

CODEX_PANE=""
if type codex_find_pane &>/dev/null; then
  CODEX_PANE=$(codex_find_pane "$PANE_ID_FILE")
elif [ -f "$PANE_ID_FILE" ]; then
  CODEX_PANE=$(cat "$PANE_ID_FILE")
fi

if [ -z "$CODEX_PANE" ]; then
  echo "Error: Codex pane not found. Run Step 3 first."
  exit 1
fi

# Use file-based response workflow if available (recommended)
if type codex_file_response_workflow &>/dev/null; then
  echo "Sending review request using file-based protocol..."

  RESPONSE=$(codex_file_response_workflow "$CODEX_PANE" "$REVIEW_PROMPT" "$WAIT_TIMEOUT")
  WORKFLOW_RESULT=$?

  if [ $WORKFLOW_RESULT -eq 0 ]; then
    echo "$RESPONSE" > "$CODEX_REVIEW"
    echo "Review response received and saved"
  else
    echo "Warning: File-based workflow returned code $WORKFLOW_RESULT, falling back to legacy"
    USE_LEGACY=true
  fi
else
  USE_LEGACY=true
fi

# Legacy fallback: codex exec in new pane
if [ "${USE_LEGACY:-}" = "true" ]; then
  PROMPT="$REVIEW_PROMPT"
  OUTPUT="$CODEX_REVIEW"
  SANDBOX="${SANDBOX_SETTING:-read-only}"
  SIGNAL="codex-review-$$-$(date +%s)-$RANDOM"

  ORIGINAL_PANE=$(tmux display-message -p '#{pane_id}')

  tmux split-window -h -d \
    "cd \"$(pwd)\"; \
     cat \"$PROMPT\" | codex exec -s \"$SANDBOX\" - 2>&1 | tee \"$OUTPUT\"; \
     echo '=== CODEX_DONE ===' >> \"$OUTPUT\"; \
     tmux wait-for -S \"$SIGNAL\""

  tmux select-pane -t "$ORIGINAL_PANE"

  echo "Codex review running in a new pane (right side)"
  echo "Signal: $SIGNAL"

  # Wait for completion
  if timeout "${WAIT_TIMEOUT}s" tmux wait-for "$SIGNAL"; then
    echo "Codex review completed"
  else
    echo "Timeout - check tmux pane or output file"
  fi
fi
```

**2a. Launch Codex for review (wt/inline mode fallback):**

For wt mode:
```bash
SANDBOX="${SANDBOX_SETTING:-read-only}"
# Note: using ; instead of && so marker is written even on Codex failure
wt.exe -w -1 -d "$(pwd)" -p Ubuntu wsl.exe zsh -i -l -c "cat \"$REVIEW_PROMPT\" | codex exec -s \"$SANDBOX\" - 2>&1 | tee \"$CODEX_REVIEW\"; echo '=== CODEX_DONE ===' >> \"$CODEX_REVIEW\""
```

> **Important:** Set Bash tool's `timeout` parameter to match or exceed `codex.wait_timeout` (in milliseconds).

**3. Wait for completion (wt/inline mode only):**

> **Note:** If you used the file-based response protocol in Step 2, skip this step.

For wt/inline mode (file polling):
```bash
# Auto-detect completion (WAIT_TIMEOUT from settings, default: 180)
for i in $(seq 1 $WAIT_TIMEOUT); do
  if grep -q "=== CODEX_DONE ===" "$CODEX_REVIEW" 2>/dev/null; then
    break
  fi
  sleep 1
done
```

### Step 8: Handle Review Result

**If PASS:**
Report completion to user with summary

**If CONDITIONAL or FAIL (with review.enabled: true):**

**8a. Review Iteration Loop:**

1. **Check if review iteration is enabled:**
   - If `review.enabled: false` → Present issues to user, no auto-iteration
   - If `review.enabled: true` → Continue with iteration

2. **Track review iteration state:**
   - Increment review round counter
   - Check if round < review.max_iterations (default: 5)

3. **Apply fixes:**
   - Address findings from the review
   - Track all modifications

4. **User confirmation (based on review.user_confirm setting):**
   - `never` (default): Auto-iterate without confirmation
   - `always`: Confirm each round
   - `on_important`: Confirm only for high-severity findings

5. **Re-request review:**
   - Stage changes with `git add -A`
   - Launch Codex with updated diff
   - Return to Step 8

6. **Force stop conditions:**
   - round >= review.max_iterations → Report remaining issues to user
   - PASS verdict received → Complete
   - User requests manual handling → Exit loop

**If review.enabled: false:**
Present issues to user and discuss next steps

### Step 9: Cleanup

**Task transition:**
1. Mark "Request review from Codex" as `completed`
2. Report completion to user

Remove temporary files:
```bash
TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
rm -f "$TMP_DIR/codex-plan-output.md" "$TMP_DIR/codex-plan-prompt.txt"
rm -f "$TMP_DIR/codex-review-output.md" "$TMP_DIR/codex-review-prompt.txt"
```

## Error Handling

**Launch mode errors:**

If `launch.mode=tmux` but not inside a tmux session:
- Error: "Not inside a tmux session. Run 'tmux' first or set launch.mode to 'wt' or 'auto'."

If `launch.mode=wt` but wt.exe is not available:
- Error: "wt.exe is not available. Set launch.mode to 'tmux' or 'auto'."

If `launch.mode=auto`:
- If inside tmux session (`$TMUX` set) → use tmux
- Else if wt.exe available → use wt
- Else → use inline
- Inform user which mode was selected

**Other errors:**

If `codex` command is not available:
- Inform user: "Codex CLI is not installed or not in PATH. Would you like to proceed with Claude-only mode?"
- If yes, continue without Codex planning/review

If Codex returns an error:
- Report the error from the output file
- Offer to retry or proceed manually

If timeout (`codex.wait_timeout`, default 180s) without completion marker:
1. **Check Codex status** - Is Codex still running in the tmux window/other pane?
2. **If still running** → Re-run wait loop with Bash `timeout` parameter extended (up to max 600000ms)
3. **If completed but marker missing** → Read partial output and report to user
4. **If Codex failed** → Report error and offer to retry or proceed manually

## Notes

- **Launch modes**:
  - **tmux** (default when in tmux): Launches Codex in **interactive mode** (`codex` not `codex exec`). The pane persists after each task and can be reused for subsequent prompts. Uses `codex_get_or_create_pane` to find existing pane or create new one.
  - **wt**: Windows Terminal new pane. May steal focus (GitHub issue #17460). Uses `codex exec` (pane closes after completion). Uses file polling for completion detection.
  - **inline**: Runs `codex exec` in current terminal. Blocks until completion.
  - **auto** (default): If inside tmux session → tmux, else → wt → inline.
- **Pane persistence (tmux mode)**:
  - Codex is launched in **interactive mode** (not `codex exec`), so the pane stays open after completion.
  - Pane ID is saved to `tmp/codex-pane-id` for reuse.
  - On subsequent invocations, the existing pane is reused instead of creating a new one.
  - The pane is verified with `codex_verify_pane` before reuse; stale panes are automatically replaced.
  - This preserves Codex's conversation context across multiple prompts.
  - To force a new pane, delete `tmp/codex-pane-id` or close the existing Codex pane.
  - **Note**: This behavior is the new default in tmux mode. The `launch.prefer_attached` setting is now redundant for tmux mode as pane reuse is always enabled. The setting remains relevant for non-tmux environments.
- **Completion detection**:
  - **tmux mode**: Uses marker (`<<RESPONSE_END_...>>`) + idle detection via `codex_wait_completion`.
  - **wt/inline mode**: Polls output file for `=== CODEX_DONE ===` marker every 1 second.
- Output files are saved in project's `tmp/` directory to share between WSL sessions. This directory is excluded by `.gitignore` so temporary files don't appear in diffs.
- **Legacy mode**: The old `codex exec` approach with signal-based completion is still documented but not the default. Use it when you need stateless execution (no context preservation).
- **Important**: Stage changes with `git add -A` before review so Codex can see new files (ensures visibility regardless of file discovery method)
- **Multi-turn exchange**: Use `next_action: continue|stop` to control exchange flow. Planning exchange max iterations default is 3.
- **Review iteration**: Enabled by default (`review.enabled: true`). Max iterations default is 5 (higher than exchange because goal is clear and diff is small).
- **Independent settings**: `exchange.*` and `review.*` are completely independent (no inheritance). Each can be configured separately.
- **Timeout configuration**: `codex.wait_timeout` (default: 180s, max: 600s) controls how long to wait for Codex. Set Bash tool's `timeout` parameter to `min(wait_timeout + 60, 600) * 1000` milliseconds.

## Compact Recovery

If you've been compacted during this workflow:

1. Run `TaskList` to see current progress
2. Find the task with status `in_progress`
3. Read `tmp/codex-pane-id` if Codex pane was attached
4. Resume from the current step

**Task to Step mapping:**
| Task | Resume at |
|------|-----------|
| "Analyze task and gather context" | Step 2 |
| "Get implementation plan from Codex" | Step 3 |
| "Review and approve plan" | Step 5 |
| "Implement changes" | Step 6 |
| "Request review from Codex" | Step 7 |

**Recovery example:**
```
TaskList shows:
- [completed] Analyze task and gather context
- [in_progress] Get implementation plan from Codex

→ Resume at Step 3: check tmp/codex-plan-output.md for Codex response
→ If output exists with completion marker → proceed to Step 5
→ If no output → re-run Codex request
```
