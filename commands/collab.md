---
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

**1. Prepare files:**
```bash
# Output file in project directory (shared between WSL sessions)
CODEX_OUTPUT="$(pwd)/.codex-plan-output.md"
CODEX_PROMPT="$(pwd)/.codex-plan-prompt.txt"
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

Provide your plan now.
EOF
```

**2. Determine launch mode:**

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

# Split current window horizontally and run Codex in the new pane
# Signal is sent even on failure (finally-style)
tmux split-window -h -d \
  "cd \"$(pwd)\"; \
   cat \"$PROMPT\" | codex exec -s \"$SANDBOX\" - 2>&1 | tee \"$OUTPUT\"; \
   echo '=== CODEX_DONE ===' >> \"$OUTPUT\"; \
   tmux wait-for -S \"$SIGNAL\""

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
git reset -- .codex-*.md .codex-*.txt 2>/dev/null || true
```
> **Why?** Staging ensures all changes are visible to Codex regardless of its file discovery method. Some tools use `git ls-files` (tracked files only) or respect `.gitignore`. Staging guarantees consistency.
> This is staging only, not a commit. Run `git reset` after review to unstage if needed.
>
> **Note:** The `git reset` line explicitly unstages temporary files (`.codex-*.md`, `.codex-*.txt`) to ensure they are not included in the review, even if the user's project doesn't have a `.gitignore` for these files.

**1. Prepare files:**
```bash
CODEX_REVIEW="$(pwd)/.codex-review-output.md"
REVIEW_PROMPT="$(pwd)/.codex-review-prompt.txt"
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

tmux split-window -h -d \
  "cd \"$(pwd)\"; \
   cat \"$PROMPT\" | codex exec -s \"$SANDBOX\" - 2>&1 | tee \"$OUTPUT\"; \
   echo '=== CODEX_DONE ===' >> \"$OUTPUT\"; \
   tmux wait-for -S \"$SIGNAL\""

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
   - Stage changes with `git add -A && git reset -- .codex-*.md .codex-*.txt 2>/dev/null || true`
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
rm -f "$(pwd)/.codex-plan-output.md" "$(pwd)/.codex-plan-prompt.txt"
rm -f "$(pwd)/.codex-review-output.md" "$(pwd)/.codex-review-prompt.txt"
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
  - **tmux**: Only works when inside a tmux session (`$TMUX` set). Splits current pane horizontally and runs Codex on the right. No focus stealing. Uses `tmux wait-for` for instant completion detection.
  - **wt**: Windows Terminal new pane. May steal focus (GitHub issue #17460). Uses file polling for completion detection.
  - **inline**: Runs in current terminal. Blocks until completion.
  - **auto** (default): If inside tmux session → tmux, else → wt → inline.
- **Completion detection**:
  - **tmux mode**: Uses `tmux wait-for` signal for instant detection (no polling). The `timeout` command wraps it for timeout support.
  - **wt/inline mode**: Polls output file for `=== CODEX_DONE ===` marker every 1 second.
- Output files are saved in project directory (not `/tmp`) to share between WSL sessions. These files (`.codex-*.md`, `.codex-*.txt`) are explicitly unstaged after `git add -A` to ensure they don't appear in review diffs
- Completion marker `=== CODEX_DONE ===` is appended to output file (kept for compatibility and debugging)
- Use `cat file | codex exec -` format to pass prompts (avoids escaping issues)
- Each Codex call is independent (no session state between calls)
- **Important**: Stage changes with `git add -A` before review so Codex can see new files (ensures visibility regardless of file discovery method)
- **Multi-turn exchange**: Use `next_action: continue|stop` to control exchange flow. Planning exchange max iterations default is 3.
- **Review iteration**: Enabled by default (`review.enabled: true`). Max iterations default is 5 (higher than exchange because goal is clear and diff is small).
- **Independent settings**: `exchange.*` and `review.*` are completely independent (no inheritance). Each can be configured separately.
- **Timeout configuration**: `codex.wait_timeout` (default: 180s, max: 600s) controls how long to wait for Codex. Set Bash tool's `timeout` parameter to `min(wait_timeout + 60, 600) * 1000` milliseconds.
