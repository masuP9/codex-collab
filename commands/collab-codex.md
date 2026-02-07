---
name: collab-codex
description: Start a collaborative task with Codex (default: codex-leads workflow)
argument-hint: [task description]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, AskUserQuestion
---

# Codex Collaboration Workflow

Execute a collaborative workflow between Claude Code and Codex CLI.

**Workflow modes** (`workflow` setting):
- **codex-leads** (従来): Codex が計画・レビュー、Claude が実装
- **claude-leads** (新規): Claude が計画・レビュー、Codex が実装（workspace-write sandbox）
- **auto** (default): 常に codex-leads を選択（明示的に `claude-leads` を指定した場合のみ Claude 主導）

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

# Source helpers with robust fallback chain
# 1. Try CLAUDE_PLUGIN_ROOT if valid
# 2. Try Claude plugin cache (latest version)
# 3. Try current directory (for development)
HELPERS=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh" ]; then
  HELPERS="${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh"
elif [ -d ~/.claude/plugins/cache/codex-collab ]; then
  HELPERS=$(ls -td ~/.claude/plugins/cache/codex-collab/codex-collab/*/scripts/codex-helpers.sh 2>/dev/null | head -1)
fi
if [ -z "$HELPERS" ] || [ ! -f "$HELPERS" ]; then
  HELPERS="$(pwd)/scripts/codex-helpers.sh"
fi
if [ -f "$HELPERS" ]; then
  source "$HELPERS"
else
  echo "Error: codex-helpers.sh not found" >&2
  echo "Tried: CLAUDE_PLUGIN_ROOT, ~/.claude/plugins/cache, $(pwd)" >&2
fi
```

> **Note:** Helper functions are required for this workflow. The loader tries multiple locations: `CLAUDE_PLUGIN_ROOT`, Claude plugin cache, and current directory.
> **Important:** The `CODEX_SKILL_CONTEXT=1` export is required for the PreToolUse hook to recognize this as skill context and allow Bash execution without blocking.

### Step 1: Load Settings

Check for project-specific settings:
- Read `.claude/codex-collab.local.md` if it exists
- Extract YAML frontmatter for: model, sandbox, codex, exchange, review, **workflow** settings
- Apply settings priority: command args > project settings > defaults

**Default settings:**
- **workflow**: auto (options: auto, codex-leads, claude-leads; auto は常に codex-leads を選択)
- model: (Codex default)
- sandbox: read-only (codex-leads) / workspace-write (claude-leads)
- language: en (Codex response language)
- **Timeout** (codex.*):
  - codex.wait_timeout: 180 (seconds, max 600)
- **Launch mode** (launch.*):
  - launch.mode: auto (options: auto, wt, tmux, inline)
  - launch.prefer_attached: true (use existing attached Codex pane if available)
- **Planning exchange** (exchange.*, codex-leads only):
  - exchange.enabled: true
  - exchange.max_iterations: 3
  - exchange.user_confirm: on_important
  - exchange.history_mode: summarize
- **Review iteration** (review.*, codex-leads only):
  - review.enabled: true
  - review.max_iterations: 5
  - review.max_verdict_retries: 3 (retries when verdict is missing/unclear)
  - review.user_confirm: never
- **Claude-leads specific** (claude_leads.*):
  - claude_leads.sandbox: workspace-write (Codex 実装用 sandbox)
  - claude_leads.consult_codex: true (壁打ちフェーズを有効化)
  - claude_leads.safety_checkpoint: stash (options: stash, wip-commit, none)
  - claude_leads.review.max_iterations: 3 (レビュー修正ループの上限)

**Language setting:**
When `language` is set to a non-English value (e.g., `ja`), all Codex prompts will be prefixed with a language directive:
```
**{language}で回答してください。**

[Original prompt content]
```

This ensures Codex responds in the specified language regardless of the prompt template language.

### Step 1a: Determine Workflow

After loading settings, determine which workflow to use:

**If `workflow` is explicitly set to `codex-leads` or `claude-leads`:**
- Use that workflow directly.

**If `workflow` is `auto` (default):**

Always select `codex-leads`.

> **Note:** `auto` は常に `codex-leads` を選択する。`claude-leads` はClaude側のコンテキスト/ターン消費が大きく、Codex実装待ちの間にタイムアウトする問題があるため、明示的に `workflow: claude-leads` を指定した場合のみ有効。

Report the selected workflow to the user:
```
Workflow: codex-leads (auto-selected, default)
```

**After workflow is determined:**
- If `codex-leads` → Continue to **Step 2** (existing workflow)
- If `claude-leads` → Jump to **Step 2c** (Claude-led workflow)

---

## Codex-Leads Workflow (従来のワークフロー)

> This is the default workflow where **Codex plans and reviews, Claude implements**.
> Active when `workflow` is `auto` (default) or explicitly set to `codex-leads`.

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
LANG_DIRECTIVE=$(codex_get_language_directive "$LANGUAGE")

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
  CODEX_PANE=$(codex_get_or_create_pane "$SANDBOX" "$PANE_ID_FILE")
  if [ -z "$CODEX_PANE" ]; then
    echo "Error: Failed to get or create Codex pane"
    exit 1
  fi
fi
```

> **Key Change**: Instead of launching `codex exec` (which exits after completion), we now launch `codex` in interactive mode. The pane persists and can be reused for subsequent prompts.

**3. Send prompt and wait for response (tmux mode):**

For tmux mode, send the prompt using chunked method and wait for completion with polling.

```bash
# Source helpers
HELPERS="${CLAUDE_PLUGIN_ROOT:-$(pwd)}/scripts/codex-helpers.sh"
[ -f "$HELPERS" ] && source "$HELPERS"

# CODEX_PANE is set from step 2
# CODEX_PROMPT file was prepared in Step 3.1
TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
WAIT_TIMEOUT="${CODEX_WAIT_TIMEOUT:-180}"

# Capture state before sending (for change detection)
BEFORE_CONTENT=$(tmux capture-pane -t "$CODEX_PANE" -p -S -5000)
BEFORE_HASH=$(echo "$BEFORE_CONTENT" | codex_hash_content)

# Send prompt using chunked method (handles long prompts)
END_MARKER=$(codex_send_prompt_chunked "$CODEX_PANE" "$(cat "$CODEX_PROMPT")")
echo "Prompt sent to Codex pane: $CODEX_PANE"
echo "Completion marker: $END_MARKER"

# Wait for completion
CODEX_WAIT_TIMEOUT="$WAIT_TIMEOUT"
codex_wait_completion "$CODEX_PANE" "$END_MARKER" "$BEFORE_HASH"

# Capture response
CODEX_OUTPUT="$TMP_DIR/codex-plan-output.md"
codex_capture_output "$CODEX_PANE" "$CODEX_OUTPUT"
echo "Codex response captured to: $CODEX_OUTPUT"
```

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
BEFORE_HASH=$(echo "$BEFORE_CONTENT" | codex_hash_content)
```

**2. Send prompt via file reference (recommended for long prompts):**
```bash
# Source helpers (if not already)
HELPERS="${CLAUDE_PLUGIN_ROOT:-$(pwd)}/scripts/codex-helpers.sh"
[ -f "$HELPERS" ] && source "$HELPERS"

# CODEX_PROMPT file was prepared in Step 3.1

# Use file reference method (avoids paste-buffer issues with long prompts)
END_MARKER=$(codex_send_prompt_file "$ATTACHED_PANE" "$CODEX_PROMPT")
echo "Prompt sent to attached Codex pane: $ATTACHED_PANE"
echo "Completion marker: $END_MARKER"
```

> **Note:** This method references the instruction file by path (`codex_send_prompt_file`) instead of pasting the full content. This avoids paste-buffer corruption issues with long prompts.

**3. Wait for completion (marker + idle detection):**
```bash
# Source helpers (if not already)
HELPERS="${CLAUDE_PLUGIN_ROOT:-$(pwd)}/scripts/codex-helpers.sh"
[ -f "$HELPERS" ] && source "$HELPERS"

# Wait for completion using marker + idle detection
CODEX_WAIT_TIMEOUT="${WAIT_TIMEOUT:-180}"
codex_wait_completion "$ATTACHED_PANE" "$END_MARKER" "$BEFORE_HASH"
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

**tmux mode with persistent pane** (marker + idle detection):

```bash
# Source helpers
HELPERS="${CLAUDE_PLUGIN_ROOT:-$(pwd)}/scripts/codex-helpers.sh"
[ -f "$HELPERS" ] && source "$HELPERS"

TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"

# CODEX_PANE, END_MARKER, BEFORE_HASH from Step 3
WAIT_TIMEOUT="${WAIT_TIMEOUT:-180}"

# Wait for completion using marker + idle detection
CODEX_WAIT_TIMEOUT="$WAIT_TIMEOUT"
codex_wait_completion "$CODEX_PANE" "$END_MARKER" "$BEFORE_HASH"

# Capture output to file for Step 5
tmux capture-pane -t "$CODEX_PANE" -p -S -5000 > "$TMP_DIR/codex-plan-output.md"
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

> **IMPORTANT**: The diff is saved to a file and referenced by path. This approach is more stable for tmux transmission (consistent prompt size) and handles large diffs reliably.
> Codex is expected to read the diff file directly. If Codex cannot access the file, it will return a `conditional` verdict indicating the need to retry with embedded diff.

```bash
TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
mkdir -p "$TMP_DIR"
CODEX_REVIEW="$TMP_DIR/codex-review-output.md"
REVIEW_PROMPT="$TMP_DIR/codex-review-prompt.txt"
DIFF_FILE="$TMP_DIR/codex-review-diff.txt"
rm -f "$CODEX_REVIEW"

# Capture the staged diff to a file
git diff --cached > "$DIFF_FILE"

# Get absolute path for Codex
DIFF_FILE_ABS="$(cd "$(dirname "$DIFF_FILE")" && pwd)/$(basename "$DIFF_FILE")"

# Source helpers for language directive
HELPERS="${CLAUDE_PLUGIN_ROOT:-$(pwd)}/scripts/codex-helpers.sh"
[ -f "$HELPERS" ] && source "$HELPERS"

# Get language setting from config (default: en)
LANGUAGE="${LANGUAGE:-en}"

# Get language directive (empty for English)
LANG_DIRECTIVE=$(codex_get_language_directive "$LANGUAGE")

cat > "$REVIEW_PROMPT" << EOF
${LANG_DIRECTIVE}Review the implementation described below.

## Original Plan
[Plan from Step 3]

## Changes Made

The diff is saved in the following file. Please read it:
\`\`\`
$DIFF_FILE_ABS
\`\`\`

If you cannot access the file, respond with:
\`\`\`
---
status: stop
verdict: conditional
message: Unable to access diff file
---
\`\`\`

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

\`\`\`
---
status: stop
verdict: pass / conditional / fail
findings:  # if any issues found
  - severity: low / medium / high
    message: description of issue
---
\`\`\`

Provide your review now.
EOF
```

> **Note:** The language directive (if configured) is automatically prepended to ensure Codex responds in the specified language.

**2. Send review request (tmux mode):**

Reuse the existing Codex pane from Step 3:

```bash
# Source helpers
HELPERS="${CLAUDE_PLUGIN_ROOT:-$(pwd)}/scripts/codex-helpers.sh"
[ -f "$HELPERS" ] && source "$HELPERS"

# Get existing Codex pane (should exist from Step 3)
TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
PANE_ID_FILE="$TMP_DIR/codex-pane-id"
WAIT_TIMEOUT="${CODEX_WAIT_TIMEOUT:-180}"

CODEX_PANE=$(codex_find_pane "$PANE_ID_FILE")

if [ -z "$CODEX_PANE" ]; then
  echo "Error: Codex pane not found. Run Step 3 first."
  exit 1
fi

# Capture state before sending
BEFORE_CONTENT=$(tmux capture-pane -t "$CODEX_PANE" -p -S -5000)
BEFORE_HASH=$(echo "$BEFORE_CONTENT" | codex_hash_content)

# Send review prompt using chunked method
END_MARKER=$(codex_send_prompt_chunked "$CODEX_PANE" "$(cat "$REVIEW_PROMPT")")
echo "Review request sent to Codex pane: $CODEX_PANE"
echo "Completion marker: $END_MARKER"
```

**2a. Launch Codex for review (wt/inline mode fallback):**

For wt mode:
```bash
SANDBOX="${SANDBOX_SETTING:-read-only}"
wt.exe -w -1 -d "$(pwd)" -p Ubuntu wsl.exe zsh -i -l -c "cat \"$REVIEW_PROMPT\" | codex exec -s \"$SANDBOX\" - 2>&1 | tee \"$CODEX_REVIEW\"; echo '=== CODEX_DONE ===' >> \"$CODEX_REVIEW\""
```

> **Important:** Set Bash tool's `timeout` parameter to match or exceed `codex.wait_timeout` (in milliseconds).

**3. Wait for completion:**

For tmux mode (marker + idle detection):
```bash
CODEX_WAIT_TIMEOUT="$WAIT_TIMEOUT"
codex_wait_completion "$CODEX_PANE" "$END_MARKER" "$BEFORE_HASH"

# Capture review output
tmux capture-pane -t "$CODEX_PANE" -p -S -5000 > "$CODEX_REVIEW"
```

For wt/inline mode (file polling):
```bash
for i in $(seq 1 $WAIT_TIMEOUT); do
  if grep -q "=== CODEX_DONE ===" "$CODEX_REVIEW" 2>/dev/null; then
    break
  fi
  sleep 1
done
```

### Step 8: Handle Review Result

**CRITICAL: Always iterate until PASS is received or max iterations reached.**

Claude must NOT give up after a single review response. The review loop should continue until:
- Verdict is `pass`
- Max iterations reached (default: 5)
- User explicitly requests to stop

**8.0 Parse verdict from response:**

Extract the verdict from Codex's response:

```bash
# Extract verdict from the captured output
# Look for "verdict:" in the metadata block or in the response text
VERDICT=$(grep -i "verdict:" "$CODEX_REVIEW" | tail -1 | sed 's/.*verdict:[[:space:]]*//' | tr '[:upper:]' '[:lower:]' | tr -d ' ')

# Also check for verdict patterns in the response body
if [ -z "$VERDICT" ] || [ "$VERDICT" = "pass/conditional/fail" ]; then
  if grep -qi "verdict.*pass" "$CODEX_REVIEW"; then
    VERDICT="pass"
  elif grep -qi "verdict.*conditional" "$CODEX_REVIEW"; then
    VERDICT="conditional"
  elif grep -qi "verdict.*fail" "$CODEX_REVIEW"; then
    VERDICT="fail"
  fi
fi

echo "Detected verdict: $VERDICT"
```

**8.1 If verdict is missing or unclear:**

This happens when Codex couldn't complete the review (e.g., couldn't access files).

1. **Check for file access failure:**
   - If response contains "Unable to access diff file" or similar → Retry with embedded diff (fallback)

2. **Retry with embedded diff** (fallback for file access failure):
   When Codex cannot read the diff file, embed the diff directly in the prompt:
   ```bash
   DIFF_CONTENT=$(cat "$DIFF_FILE")
   cat > "$REVIEW_PROMPT" << EOF
   前回、差分ファイルにアクセスできなかったようです。
   差分を直接含めて再度レビューをお願いします。

   ## 差分

   \`\`\`diff
   ${DIFF_CONTENT}
   \`\`\`

   verdict: pass / conditional / fail で回答してください。
   EOF
   ```

3. **Retry with simplified prompt** (up to 3 retries):
   - If still no verdict, send a follow-up prompt asking for explicit verdict:
   ```
   前回の応答でverdictが確認できませんでした。

   上記の差分を確認して、以下の形式で回答してください：

   verdict: pass / conditional / fail

   （理由がある場合は簡潔に）
   ```

4. **If still no verdict after retries:**
   - Log warning: "Could not get verdict from Codex after 3 retries"
   - Treat as `conditional` and continue to 8.3

**8.2 If PASS:**

Report completion to user with summary. Task complete.

**8.3 If CONDITIONAL:**

Conditional means the implementation is acceptable but has room for improvement.

1. **Check for specific findings:**
   - If Codex provided specific issues → Apply fixes and re-request review
   - If no specific issues (e.g., "couldn't access files") → Ask Codex to re-review with diff provided

2. **Re-review with clarification:**
   ```
   前回「conditional」でしたが、具体的な修正点が不明確でした。

   以下の差分を確認し、具体的な問題があれば指摘してください。
   問題がなければ「verdict: pass」としてください。

   [diff content]
   ```

3. **Continue iteration** until pass or max iterations

**8.4 If FAIL:**

1. **Extract specific issues** from the review
2. **Apply fixes** based on Codex's feedback
3. **Stage changes:** `git add -A`
4. **Re-request review** with updated diff
5. **Return to Step 8**

**8a. Review Iteration Loop (Full Implementation):**

```
review_round = 0
max_rounds = review.max_iterations (default: 5)
verdict_retries = 0
max_verdict_retries = 3
diff_embedded = false  # Track if we've switched to embedded diff mode

WHILE review_round < max_rounds:
  review_round++

  1. Send review request to Codex (file reference or embedded diff)
  2. Wait for completion
  3. Parse verdict

  IF response contains "Unable to access diff file":
    # Fallback: retry with embedded diff
    diff_embedded = true
    Rebuild prompt with diff content embedded
    review_round--  # Don't count this as a full round
    CONTINUE

  IF verdict is missing:
    verdict_retries++
    IF verdict_retries < max_verdict_retries:
      Send follow-up asking for explicit verdict
      CONTINUE (don't increment review_round)
    ELSE:
      verdict = "conditional" (fallback)

  IF verdict == "pass":
    BREAK → Success

  IF verdict == "conditional":
    IF specific_findings_exist:
      Apply fixes
    ELSE:
      Re-request with clarification
    CONTINUE

  IF verdict == "fail":
    Apply fixes based on findings
    CONTINUE

IF review_round >= max_rounds AND verdict != "pass":
  Report: "Max review iterations reached. Final verdict: {verdict}"
  Ask user if they want to continue or accept current state
```

**User confirmation (based on review.user_confirm setting):**
- `never` (default): Auto-iterate without confirmation
- `always`: Confirm each round
- `on_important`: Confirm only for high-severity findings

**Force stop conditions:**
- round >= review.max_iterations → Report to user, ask for direction
- User explicitly cancels
- Repeated identical feedback (infinite loop detection)

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

---

## Claude-Leads Workflow (新規ワークフロー)

> This workflow has **Claude plan and review, Codex implement**.
> Active only when `workflow` is explicitly set to `claude-leads`.
>
> **Key difference**: Codex runs with `workspace-write` sandbox to make file changes directly.

**Responsibility Boundary:**
| Role | Responsibility |
|------|---------------|
| **Claude** | Quality gate: deep analysis, planning, review, approval |
| **Codex** | Execution engine: accurate implementation per plan |
| **User** | Final approval: plan approval and ultimate decision authority |

> Claude bears responsibility for plan quality and review thoroughness. Codex bears responsibility for faithful execution. The user has final say at the plan approval step (Step 5c).

### Step 2c: Deep Codebase Analysis (Claude)

**Create a task to track progress:**

Use TaskCreate:
- subject: "Deep codebase analysis for planning"
- description: "Analyze codebase, identify affected files, understand architecture"
- activeForm: "Analyzing codebase"

Then use TaskUpdate to set status to `in_progress`.

**Perform deep analysis:**

Claude should thoroughly analyze the codebase using Read, Glob, and Grep:

1. **Understand the task**: Parse the core objective from the task description
2. **Map affected files**: Use Glob and Grep to find all relevant files
3. **Read key files**: Read each affected file to understand current implementation
4. **Understand dependencies**: Trace imports, function calls, and data flow
5. **Check existing tests**: Find related test files and understand test patterns
6. **Review recent changes**: Use `git log` to understand recent context

> **Note:** This is where Claude's strength in deep reasoning shines. Take time to thoroughly understand the codebase before creating a plan.

### Step 3c: Create Detailed Implementation Plan (Claude)

**Task transition:**
1. Mark "Deep codebase analysis for planning" as `completed`
2. Use TaskCreate:
   - subject: "Create implementation plan"
   - description: "Design detailed step-by-step plan based on analysis"
   - activeForm: "Creating plan"
3. Use TaskUpdate to set status to `in_progress`

Based on the analysis, create a detailed implementation plan that includes:

1. **Files to Modify**: List each file with type of change (create/modify/delete)
2. **Implementation Steps**: Numbered steps in execution order with specific code changes
3. **Risk Assessment**: Potential issues and edge cases
4. **Test Considerations**: What should be tested

Format the plan clearly so it can be:
- Presented to the user for approval
- Sent to Codex as implementation instructions

### Step 4c: Plan Consultation with Codex (Optional)

> This step is optional and controlled by `claude_leads.consult_codex` setting (default: true).
> Skip this step if `consult_codex: false`.

**Purpose:** Get Codex's perspective on the plan before implementation. This is a "壁打ち" (wall-hitting / brainstorming) phase.

**1. Prepare consultation prompt:**

```bash
export CODEX_SKILL_CONTEXT=1

# Source helpers
HELPERS=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh" ]; then
  HELPERS="${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh"
elif [ -d ~/.claude/plugins/cache/codex-collab ]; then
  HELPERS=$(ls -td ~/.claude/plugins/cache/codex-collab/codex-collab/*/scripts/codex-helpers.sh 2>/dev/null | head -1)
fi
if [ -z "$HELPERS" ] || [ ! -f "$HELPERS" ]; then
  HELPERS="$(pwd)/scripts/codex-helpers.sh"
fi
[ -f "$HELPERS" ] && source "$HELPERS"

TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
mkdir -p "$TMP_DIR"
CONSULT_PROMPT="$TMP_DIR/codex-consult-prompt.txt"
CONSULT_OUTPUT="$TMP_DIR/codex-consult-output.md"
rm -f "$CONSULT_OUTPUT"

LANGUAGE="${LANGUAGE:-en}"
LANG_DIRECTIVE=$(codex_get_language_directive "$LANGUAGE")

cat > "$CONSULT_PROMPT" << EOF
${LANG_DIRECTIVE}You are reviewing an implementation plan created by Claude Code before execution.

**IMPORTANT**: If you reference any files, always re-read them from disk.

## Task
[Task description]

## Proposed Plan
[Claude's implementation plan from Step 3c]

## Review Request

Please review this plan and provide feedback on:

### 1. Feasibility
Can this plan be executed as-is? Any missing steps?

### 2. Risks
Any risks or edge cases not covered?

### 3. Improvements
Suggestions for better approach or optimization?

### 4. Verdict
- APPROVE: Plan is solid, proceed with implementation
- SUGGEST: Plan is acceptable with suggested improvements
- RETHINK: Significant issues, plan needs revision

## Response Format

At the end of your response, include a metadata block:

\`\`\`
---
status: stop
verdict: approve / suggest / rethink
suggestions:
  - suggestion 1
---
\`\`\`

Provide your review now.
EOF
```

**2. Send to Codex and wait for response:**

Use the same pane management as the codex-leads workflow (get or create pane, send prompt, wait for completion).

**3. Process Codex's feedback:**

- If `verdict: approve` → Proceed to Step 5c
- If `verdict: suggest` → Incorporate suggestions into the plan, proceed to Step 5c
- If `verdict: rethink` → Revise plan based on feedback, optionally re-consult

### Step 5c: User Approval

**Task transition:**
1. Mark "Create implementation plan" as `completed`
2. Use TaskCreate:
   - subject: "Get user approval for plan"
   - description: "Present plan (with Codex feedback if available) for user approval"
   - activeForm: "Waiting for user approval"
3. Use TaskUpdate to set status to `in_progress`

Present the plan to the user, including Codex's feedback if consultation was performed.

Use AskUserQuestion to get user approval:
- Show the plan summary
- If Codex suggested improvements, highlight them
- Ask user to approve, modify, or reject the plan

**If user approves** → Continue to Step 6c
**If user requests modifications** → Update plan and re-present
**If user rejects** → End workflow

### Step 6c: Safety Checkpoint

**Before Codex makes any changes, save the current state.**

Based on `claude_leads.safety_checkpoint` setting:

**`stash` (default):**
```bash
export CODEX_SKILL_CONTEXT=1
# Save current state
git stash push -m "codex-collab: pre-implementation checkpoint $(date +%Y%m%d-%H%M%S)"
echo "Safety checkpoint created (git stash)"
```

**`wip-commit`:**
```bash
export CODEX_SKILL_CONTEXT=1
git add -A
git commit -m "WIP: codex-collab pre-implementation checkpoint" --allow-empty
echo "Safety checkpoint created (WIP commit)"
```

**`none`:**
- Skip checkpoint (user accepts risk)

> **Important:** The safety checkpoint ensures you can always revert Codex's changes if something goes wrong. Use `git stash pop` or `git reset HEAD~1` to restore.

### Step 7c: Codex Implementation

**Task transition:**
1. Mark "Get user approval for plan" as `completed`
2. Use TaskCreate:
   - subject: "Codex implements changes"
   - description: "Send plan to Codex with workspace-write sandbox, monitor implementation"
   - activeForm: "Codex implementing"
3. Use TaskUpdate to set status to `in_progress`

**1. Prepare implementation prompt:**

```bash
export CODEX_SKILL_CONTEXT=1

# Source helpers
HELPERS=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh" ]; then
  HELPERS="${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh"
elif [ -d ~/.claude/plugins/cache/codex-collab ]; then
  HELPERS=$(ls -td ~/.claude/plugins/cache/codex-collab/codex-collab/*/scripts/codex-helpers.sh 2>/dev/null | head -1)
fi
if [ -z "$HELPERS" ] || [ ! -f "$HELPERS" ]; then
  HELPERS="$(pwd)/scripts/codex-helpers.sh"
fi
[ -f "$HELPERS" ] && source "$HELPERS"

TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
mkdir -p "$TMP_DIR"
IMPL_PROMPT="$TMP_DIR/codex-impl-prompt.txt"
IMPL_OUTPUT="$TMP_DIR/codex-impl-output.md"
rm -f "$IMPL_OUTPUT"

LANGUAGE="${LANGUAGE:-en}"
LANG_DIRECTIVE=$(codex_get_language_directive "$LANGUAGE")

cat > "$IMPL_PROMPT" << EOF
${LANG_DIRECTIVE}You are implementing changes based on a plan created by Claude Code.

**IMPORTANT**: Execute the plan exactly as specified. If you encounter issues, describe them clearly.

## Task
[Task description]

## Implementation Plan
[Detailed plan from Step 3c, with any modifications from consultation/user feedback]

## Instructions

1. Implement each step in order
2. Create/modify/delete files as specified
3. Follow existing code style and patterns
4. Do NOT skip any steps

## Response Format

After implementation, include a metadata block:

\`\`\`
---
status: stop
files_changed:
  - path/to/file1.ts (modified)
  - path/to/file2.ts (created)
issues:
  - description of any issues encountered
---
\`\`\`

Begin implementation now.
EOF
```

**2. Get or create Codex pane with workspace-write sandbox:**

```bash
export CODEX_SKILL_CONTEXT=1

# Source helpers
HELPERS=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh" ]; then
  HELPERS="${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh"
elif [ -d ~/.claude/plugins/cache/codex-collab ]; then
  HELPERS=$(ls -td ~/.claude/plugins/cache/codex-collab/codex-collab/*/scripts/codex-helpers.sh 2>/dev/null | head -1)
fi
if [ -z "$HELPERS" ] || [ ! -f "$HELPERS" ]; then
  HELPERS="$(pwd)/scripts/codex-helpers.sh"
fi
[ -f "$HELPERS" ] && source "$HELPERS"

TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
mkdir -p "$TMP_DIR"
PANE_ID_FILE="$TMP_DIR/codex-pane-id"

# Claude-leads uses workspace-write sandbox for implementation
SANDBOX="${CLAUDE_LEADS_SANDBOX:-workspace-write}"

# Determine launch mode
LAUNCH_MODE="inline"
if [ -n "$TMUX" ]; then
  LAUNCH_MODE="tmux"
elif command -v wt.exe &>/dev/null; then
  LAUNCH_MODE="wt"
fi
echo "Using launch mode: $LAUNCH_MODE (sandbox: $SANDBOX)"

# For tmux mode: get or create persistent Codex pane
CODEX_PANE=""
if [ "$LAUNCH_MODE" = "tmux" ]; then
  CODEX_PANE=$(codex_get_or_create_pane "$SANDBOX" "$PANE_ID_FILE")
  if [ -z "$CODEX_PANE" ]; then
    echo "Error: Failed to get or create Codex pane"
    exit 1
  fi
fi
```

> **Important:** The sandbox is set to `workspace-write` (configurable via `claude_leads.sandbox`). This allows Codex to create and modify files within the project directory.

**3. Send implementation prompt and wait:**

Use the same send/wait pattern as the codex-leads workflow (chunked send + wait_completion).

**4. Launch Codex (wt/inline mode fallback):**

For non-tmux environments, use `codex exec` with workspace-write sandbox:

**wt mode:**
```bash
SANDBOX="${CLAUDE_LEADS_SANDBOX:-workspace-write}"
wt.exe -w -1 -d "$(pwd)" -p Ubuntu wsl.exe zsh -i -l -c "cat \"$IMPL_PROMPT\" | codex exec -s \"$SANDBOX\" - 2>&1 | tee \"$IMPL_OUTPUT\"; echo '=== CODEX_DONE ===' >> \"$IMPL_OUTPUT\""
```

**inline mode:**
```bash
SANDBOX="${CLAUDE_LEADS_SANDBOX:-workspace-write}"
cat "$IMPL_PROMPT" | codex exec -s "$SANDBOX" - 2>&1 | tee "$IMPL_OUTPUT"; echo '=== CODEX_DONE ===' >> "$IMPL_OUTPUT"
```

### Step 8c: Claude Review

**Task transition:**
1. Mark "Codex implements changes" as `completed`
2. Use TaskCreate:
   - subject: "Review Codex's implementation"
   - description: "Review changes via git diff and file reading, verify correctness"
   - activeForm: "Reviewing implementation"
3. Use TaskUpdate to set status to `in_progress`

**Claude reviews the changes made by Codex:**

**Roles (claude-leads):**
- **Claude**: Quality gate — responsible for plan, review, and approval
- **Codex**: Execution engine — responsible for accurate implementation per plan
- **User**: Final approval authority

1. **Check git diff:**
```bash
export CODEX_SKILL_CONTEXT=1
git diff
git diff --stat
```

2. **CRITICAL: Plan-vs-diff validation (mandatory):**
   Compare `git diff --stat` output against the file list in the implementation plan (Step 3c).
   - If files **outside the plan** are modified → **immediately halt** and report to user
   - Ask user whether to: (a) accept the extra changes, (b) revert them, or (c) abort entirely
   - This is a safety guard since workspace-write sandbox cannot prevent Codex from modifying unplanned files

3. **Read modified files:** Use Read tool to examine each changed file
4. **Verify against plan:** Check that each step was implemented correctly
5. **Check for issues:**
   - Code quality and style consistency
   - Security vulnerabilities
   - Missing error handling
   - Test coverage gaps
6. **Run lint/test if available:** If the project has lint or test commands configured, run them to catch issues automatically

### Step 9c: Fix Iteration & Completion

**Review iteration loop (Claude-led):**

```
review_round = 0
max_rounds = claude_leads.review.max_iterations (default: 3)

WHILE review_round < max_rounds:
  review_round++

  1. Claude reviews changes (git diff + Read)
  2. IF issues found:
     a. Prepare fix instructions for Codex
     b. Send fix prompt to Codex (workspace-write sandbox)
     c. Wait for Codex completion
     d. CONTINUE (re-review)
  3. IF no issues:
     BREAK → Success

IF review_round >= max_rounds AND issues remain:
  Report: "Max review iterations reached. Remaining issues:"
  List remaining issues
  Ask user for direction
```

**Fix prompt template:**

```bash
export CODEX_SKILL_CONTEXT=1

# Source helpers
HELPERS=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh" ]; then
  HELPERS="${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh"
elif [ -d ~/.claude/plugins/cache/codex-collab ]; then
  HELPERS=$(ls -td ~/.claude/plugins/cache/codex-collab/codex-collab/*/scripts/codex-helpers.sh 2>/dev/null | head -1)
fi
if [ -z "$HELPERS" ] || [ ! -f "$HELPERS" ]; then
  HELPERS="$(pwd)/scripts/codex-helpers.sh"
fi
[ -f "$HELPERS" ] && source "$HELPERS"

TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
FIX_PROMPT="$TMP_DIR/codex-fix-prompt.txt"

LANGUAGE="${LANGUAGE:-en}"
LANG_DIRECTIVE=$(codex_get_language_directive "$LANGUAGE")

cat > "$FIX_PROMPT" << EOF
${LANG_DIRECTIVE}Fix the following issues found during review.

## Issues to Fix
[List of specific issues with file paths and line numbers]

## Instructions
1. Fix each issue as described
2. Do not change anything else
3. Preserve existing code style

## Response Format
\`\`\`
---
status: stop
fixes_applied:
  - description of fix 1
  - description of fix 2
---
\`\`\`
EOF
```

**Completion:**

1. Mark "Review Codex's implementation" as `completed`
2. **Cleanup temporary files:**
```bash
export CODEX_SKILL_CONTEXT=1
TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
rm -f "$TMP_DIR/codex-consult-prompt.txt" "$TMP_DIR/codex-consult-output.md"
rm -f "$TMP_DIR/codex-impl-prompt.txt" "$TMP_DIR/codex-impl-output.md"
rm -f "$TMP_DIR/codex-fix-prompt.txt"
```
3. Report completion to user with summary of changes

---

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

- **Workflow modes**:
  - **codex-leads**: Traditional workflow. Codex plans/reviews, Claude implements. Uses `read-only` sandbox by default.
  - **claude-leads**: New workflow. Claude plans/reviews, Codex implements. Uses `workspace-write` sandbox by default.
  - **auto**: 常に `codex-leads` を選択。`claude-leads` は明示的に `workflow: claude-leads` を指定した場合のみ有効。
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
- **Multi-turn exchange** (codex-leads only): Use `next_action: continue|stop` to control exchange flow. Planning exchange max iterations default is 3.
- **Review iteration** (codex-leads): Enabled by default (`review.enabled: true`). **Claude must NOT give up after a single review** - continue iterating until `pass` is received or max iterations (default: 5) is reached. If verdict is missing/unclear, retry up to 3 times before treating as `conditional`. Always include the actual diff in review prompts so Codex can review without file access.
- **Claude-led review** (claude-leads): Claude reviews Codex's changes via `git diff` + Read. If issues found, sends fix instructions to Codex. Max iterations controlled by `claude_leads.review.max_iterations` (default: 3).
- **Safety checkpoint** (claude-leads): Before Codex implementation, save state via git stash (default), WIP commit, or skip. Configurable via `claude_leads.safety_checkpoint`.
- **Plan consultation** (claude-leads): Optional Codex review of Claude's plan before implementation. Controlled by `claude_leads.consult_codex` (default: true).
- **Independent settings**: `exchange.*` and `review.*` are completely independent (no inheritance). Each can be configured separately. `claude_leads.*` settings are only used in claude-leads workflow.
- **Timeout configuration**: `codex.wait_timeout` (default: 180s, max: 600s) controls how long to wait for Codex. Set Bash tool's `timeout` parameter to `min(wait_timeout + 60, 600) * 1000` milliseconds.

## Compact Recovery

If you've been compacted during this workflow:

1. Run `TaskList` to see current progress
2. Find the task with status `in_progress`
3. Read `tmp/codex-pane-id` if Codex pane was attached
4. Resume from the current step

**Task to Step mapping (codex-leads):**
| Task | Resume at |
|------|-----------|
| "Analyze task and gather context" | Step 2 |
| "Get implementation plan from Codex" | Step 3 |
| "Review and approve plan" | Step 5 |
| "Implement changes" | Step 6 |
| "Request review from Codex" | Step 7 |

**Task to Step mapping (claude-leads):**
| Task | Resume at |
|------|-----------|
| "Deep codebase analysis for planning" | Step 2c |
| "Create implementation plan" | Step 3c |
| "Get user approval for plan" | Step 5c |
| "Codex implements changes" | Step 7c |
| "Review Codex's implementation" | Step 8c |

**Recovery example (codex-leads):**
```
TaskList shows:
- [completed] Analyze task and gather context
- [in_progress] Get implementation plan from Codex

→ Resume at Step 3: check tmp/codex-plan-output.md for Codex response
→ If output exists with completion marker → proceed to Step 5
→ If no output → re-run Codex request
```

**Recovery example (claude-leads):**
```
TaskList shows:
- [completed] Deep codebase analysis for planning
- [completed] Create implementation plan
- [in_progress] Codex implements changes

→ Resume at Step 7c: check tmp/codex-impl-output.md for Codex response
→ If output exists → proceed to Step 8c (Claude Review)
→ If no output → re-send implementation prompt
```
