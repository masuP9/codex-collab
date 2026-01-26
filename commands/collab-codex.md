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

Source shared helper functions at the beginning of any bash block:
```bash
# Source helpers (assumes running from plugin root or project root)
HELPERS="${CLAUDE_PLUGIN_ROOT:-$(pwd)}/scripts/codex-helpers.sh"
if [ -f "$HELPERS" ]; then
  source "$HELPERS"
fi
```

> **Note:** If helpers are not available, the bash blocks include inline fallback definitions where necessary.

### Step 1: Load Settings

Check for project-specific settings:
- Read `.claude/codex-collab.local.md` if it exists
- Extract YAML frontmatter for: model, sandbox, codex, exchange, review settings
- Apply settings priority: command args > project settings > defaults

**Default settings:**
- model: (Codex default)
- sandbox: read-only
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

### Step 2: Analyze Task

Before requesting a plan from Codex:
1. Identify the core objective from the task description
2. List potentially affected files
3. Gather relevant context by reading key files
4. Prepare a summary for Codex

### Step 3: Request Plan from Codex

Launch Codex based on `launch.mode` setting. Output is saved to project directory for sharing between sessions.

**1. Prepare files (always run first):**
```bash
# Ensure tmp directory exists and set output file paths
TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
mkdir -p "$TMP_DIR"
CODEX_OUTPUT="$TMP_DIR/codex-plan-output.md"
CODEX_PROMPT="$TMP_DIR/codex-plan-prompt.txt"
rm -f "$CODEX_OUTPUT"

# Write prompt to file
cat > "$CODEX_PROMPT" << 'EOF'
You are collaborating with Claude Code. Your role is to create a detailed implementation plan.

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

Use `status: continue` if you have questions, `status: stop` if the plan is complete.

Provide your plan now.
EOF
```

**2. Check for attached Codex pane (if launch.prefer_attached: true):**

If `launch.prefer_attached` is enabled (default: true) and inside tmux, check for an existing attached Codex pane:

```bash
# Source helpers
HELPERS="${CLAUDE_PLUGIN_ROOT:-$(pwd)}/scripts/codex-helpers.sh"
[ -f "$HELPERS" ] && source "$HELPERS"

# PREFER_ATTACHED should be set from launch.prefer_attached setting in Step 1
# Default: true (enabled)
# Set PREFER_ATTACHED="false" to skip attached pane checks

# Skip if not in tmux or prefer_attached is disabled
if [ -n "$TMUX" ] && [ "${PREFER_ATTACHED:-true}" = "true" ]; then
  TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
  PANE_ID_FILE="$TMP_DIR/codex-pane-id"
  ATTACHED_PANE=""

  # Use helper function for pane detection (handles stored ID + auto-detect)
  if type codex_find_pane &>/dev/null; then
    ATTACHED_PANE=$(codex_find_pane "$PANE_ID_FILE")
  else
    # Inline fallback if helpers not available
    if [ -f "$PANE_ID_FILE" ]; then
      STORED_PANE=$(cat "$PANE_ID_FILE")
      if tmux list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qx "$STORED_PANE"; then
        PANE_CMD=$(tmux display-message -t "$STORED_PANE" -p '#{pane_current_command}' 2>/dev/null)
        PANE_CONTENT=$(tmux capture-pane -t "$STORED_PANE" -p -S -2000 2>/dev/null)
        if [ "$PANE_CMD" = "node" ] && echo "$PANE_CONTENT" | grep -q "│ >_ OpenAI Codex"; then
          ATTACHED_PANE="$STORED_PANE"
          echo "Found attached Codex pane: $ATTACHED_PANE"
        fi
      fi
    fi
  fi

  # *** CONTROL FLOW ***
  # If attached pane found, skip to Step 3-Attached and do NOT run Step 3/4
  if [ -n "$ATTACHED_PANE" ]; then
    echo "Using attached Codex pane instead of launching new instance"
    # → Skip Steps 3-4, go directly to Step 3-Attached
  fi
fi
```

> **Control Flow Note**: If `ATTACHED_PANE` is set after this check, skip Steps 3-4 entirely and proceed to **Step 3-Attached**. The workflow branches here based on whether an attached pane was found.

**3. Determine launch mode:**

Apply launch mode based on `launch.mode` setting:
- **auto** (default): If inside tmux session → tmux, else → wt.exe → inline
- **tmux**: Force tmux mode (error if not in tmux session)
- **wt**: Force Windows Terminal mode (error if wt.exe not available)
- **inline**: Force inline mode (blocks terminal until completion)

> **Note:** tmux mode only works when already inside a tmux session (`$TMUX` is set). This splits the current pane horizontally and runs Codex on the right side. Outside tmux, wt.exe provides real-time output visibility.

```bash
# Read settings from .claude/codex-collab.local.md (YAML frontmatter)
# LAUNCH_MODE_SETTING = launch.mode from settings (default: auto)
# SANDBOX_SETTING = sandbox from settings (default: read-only)
# MODEL_SETTING = model from settings (optional)

# Validate and resolve launch mode
case "$LAUNCH_MODE_SETTING" in
  tmux)
    if [ -z "$TMUX" ]; then
      echo "Error: Not inside a tmux session. Run 'tmux' first or set launch.mode to 'wt' or 'auto'."
      exit 1
    fi
    LAUNCH_MODE="tmux"
    ;;
  wt)
    if ! command -v wt.exe &>/dev/null; then
      echo "Error: wt.exe is not available. Set launch.mode to 'tmux' or 'auto'."
      exit 1
    fi
    LAUNCH_MODE="wt"
    ;;
  inline)
    LAUNCH_MODE="inline"
    ;;
  auto|*)
    # Auto-detect: if in tmux → tmux, else → wt → inline
    LAUNCH_MODE="inline"
    if [ -n "$TMUX" ]; then
      LAUNCH_MODE="tmux"
    elif command -v wt.exe &>/dev/null; then
      LAUNCH_MODE="wt"
    fi
    ;;
esac
echo "Using launch mode: $LAUNCH_MODE"
```

**3. Launch Codex:**

**tmux mode** (recommended - no focus stealing, uses `tmux wait-for` for instant completion detection):
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

> **Important:** Set the Bash tool's `timeout` parameter to `min(wait_timeout + 60, 600) * 1000` milliseconds. Example: for 180s wait, use `timeout: 240000`. Max: 600000ms (10 minutes).

**tmux mode** (signal-based, instant detection):
```bash
# WAIT_TIMEOUT from settings (default: 180 seconds)
# SIGNAL from Step 3
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
3. If completed but signal/marker missing → Read partial output and report error
4. If failed → Report error and offer to retry

### Step 5: Read and Process Response

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

Execute the plan step by step:
1. Make changes as specified
2. Track all modifications
3. Prepare diff summary for review

### Step 7: Request Review from Codex (New Pane)

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

cat > "$REVIEW_PROMPT" << 'EOF'
Review the implementation described below.

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

**2. Launch Codex for review:**

Use the same launch mode as Step 3. For tmux mode:
```bash
# Run Codex review in a new pane with signal-based completion
PROMPT="$REVIEW_PROMPT"
OUTPUT="$CODEX_REVIEW"
SANDBOX="${SANDBOX_SETTING:-read-only}"
# Unique signal: PID + timestamp + random suffix to avoid collisions
SIGNAL="codex-review-$$-$(date +%s)-$RANDOM"

# Capture original pane ID to ensure focus returns after split
ORIGINAL_PANE=$(tmux display-message -p '#{pane_id}')

tmux split-window -h -d \
  "cd \"$(pwd)\"; \
   cat \"$PROMPT\" | codex exec -s \"$SANDBOX\" - 2>&1 | tee \"$OUTPUT\"; \
   echo '=== CODEX_DONE ===' >> \"$OUTPUT\"; \
   tmux wait-for -S \"$SIGNAL\""

# Ensure focus returns to original pane (safety net for -d flag inconsistencies)
tmux select-pane -t "$ORIGINAL_PANE"

echo "Codex review running in a new pane (right side)"
echo "Signal: $SIGNAL"
```

For wt mode:
```bash
SANDBOX="${SANDBOX_SETTING:-read-only}"
# Note: using ; instead of && so marker is written even on Codex failure
wt.exe -w -1 -d "$(pwd)" -p Ubuntu wsl.exe zsh -i -l -c "cat \"$REVIEW_PROMPT\" | codex exec -s \"$SANDBOX\" - 2>&1 | tee \"$CODEX_REVIEW\"; echo '=== CODEX_DONE ===' >> \"$CODEX_REVIEW\""
```

> **Important:** Set Bash tool's `timeout` parameter to match or exceed `codex.wait_timeout` (in milliseconds).

**3. Wait for completion:**

For tmux mode (signal-based):
```bash
# SIGNAL from step 2
if timeout "${WAIT_TIMEOUT}s" tmux wait-for "$SIGNAL"; then
  echo "Codex review completed"
else
  echo "Timeout - check tmux pane or output file"
fi
```

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
  - **attached**: Uses existing Codex pane (from `/collab-attach`). No new pane created. Uses marker + idle detection for completion. Enabled by `launch.prefer_attached: true` (default).
  - **tmux**: Only works when inside a tmux session (`$TMUX` set). Splits current pane horizontally and runs Codex on the right. No focus stealing. Uses `tmux wait-for` for instant completion detection.
  - **wt**: Windows Terminal new pane. May steal focus (GitHub issue #17460). Uses file polling for completion detection.
  - **inline**: Runs in current terminal. Blocks until completion.
  - **auto** (default): If inside tmux session → tmux, else → wt → inline.
- **Attached pane priority**: When `launch.prefer_attached: true` (default), `/collab` first checks for `tmp/codex-pane-id`. If a valid Codex pane exists, prompts are sent there instead of launching a new instance. This preserves conversation context from `/collab-attach` sessions. Set `launch.prefer_attached: false` to always launch new instances.
- **Completion detection**:
  - **tmux mode**: Uses `tmux wait-for` signal for instant detection (no polling). The `timeout` command wraps it for timeout support.
  - **wt/inline mode**: Polls output file for `=== CODEX_DONE ===` marker every 1 second.
- Output files are saved in project's `tmp/` directory to share between WSL sessions. This directory is excluded by `.gitignore` so temporary files don't appear in diffs.
- Completion marker `=== CODEX_DONE ===` is appended to output file (kept for compatibility and debugging)
- Use `cat file | codex exec -` format to pass prompts (avoids escaping issues)
- Each Codex call is independent (no session state between calls)
- **Important**: Stage changes with `git add -A` before review so Codex can see new files (ensures visibility regardless of file discovery method)
- **Multi-turn exchange**: Use `next_action: continue|stop` to control exchange flow. Planning exchange max iterations default is 3.
- **Review iteration**: Enabled by default (`review.enabled: true`). Max iterations default is 5 (higher than exchange because goal is clear and diff is small).
- **Independent settings**: `exchange.*` and `review.*` are completely independent (no inheritance). Each can be configured separately.
- **Timeout configuration**: `codex.wait_timeout` (default: 180s, max: 600s) controls how long to wait for Codex. Set Bash tool's `timeout` parameter to `min(wait_timeout + 60, 600) * 1000` milliseconds.
