---
description: Start a collaborative task with Codex (Codex plans/reviews, Claude implements)
argument-hint: [task description]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, AskUserQuestion
---

# Codex Collaboration Workflow

Execute a collaborative workflow between Claude Code and Codex CLI.

**WSL環境**: Codexは新しいペインで起動するため、リアルタイムで出力を確認できます。完了は自動検知されます。
**その他の環境**: 現在のターミナルで実行されます（完了まで出力は表示されません）。

## Task

$ARGUMENTS

## Workflow Instructions

### Step 1: Load Settings

Check for project-specific settings:
- Read `.claude/codex-collab.local.md` if it exists
- Extract YAML frontmatter for: model, sandbox, exchange, review settings
- Apply settings priority: command args > project settings > defaults

**Default settings:**
- model: (Codex default)
- sandbox: read-only
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

### Step 3: Request Plan from Codex (New Pane)

Launch Codex in a new pane. Output is saved to project directory for sharing between WSL sessions.

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

**2. Launch Codex in new pane (WSL/Windows Terminal):**
```bash
wt.exe -w -1 -d "$(pwd)" -p Ubuntu wsl.exe zsh -i -l -c "cat [PROMPT_FILE] | codex exec -s read-only - 2>&1 | tee [OUTPUT_FILE] && echo '=== CODEX_DONE ===' >> [OUTPUT_FILE]"
```

Replace `[PROMPT_FILE]` and `[OUTPUT_FILE]` with absolute paths.

**Options to include based on settings:**
- `-m, --model <model>` - Specify model (e.g., o4-mini, o3)
- `-s, --sandbox <mode>` - read-only | workspace-write | danger-full-access

### Step 4: Wait for Codex Completion (Auto-detect)

Poll the output file for the completion marker:

```bash
echo "Waiting for Codex..."
for i in {1..120}; do
  if grep -q "=== CODEX_DONE ===" "$CODEX_OUTPUT" 2>/dev/null; then
    echo "Codex completed after ${i}s"
    break
  fi
  sleep 1
done
```

Timeout after 120 seconds. If timeout, ask user if Codex is still running.

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

**2. Launch Codex and wait for completion:**
```bash
wt.exe -w -1 -d "$(pwd)" -p Ubuntu wsl.exe zsh -i -l -c "cat [REVIEW_PROMPT] | codex exec -s read-only - 2>&1 | tee [CODEX_REVIEW] && echo '=== CODEX_DONE ===' >> [CODEX_REVIEW]"

# Auto-detect completion
for i in {1..120}; do
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

If `wt.exe` is not available (non-WSL/Linux環境):
- Fall back to `codex exec` in current terminal
- Inform user: "WSL環境ではないため、現在のターミナルでCodexを実行します。完了まで出力は表示されません。"
- 出力はファイルに保存されるので、完了後に結果を確認できます

If `codex` command is not available:
- Inform user: "Codex CLI is not installed or not in PATH. Would you like to proceed with Claude-only mode?"
- If yes, continue without Codex planning/review

If Codex returns an error:
- Report the error from the output file
- Offer to retry or proceed manually

If timeout (120s) without completion marker:
- Ask user if Codex is still running
- Offer to extend wait time or read partial output

## Notes

- **WSL環境**: 新しいペインでCodexが起動し、リアルタイムで出力を確認可能。完了は自動検知。
- **その他の環境**: 現在のターミナルで実行（完了まで出力は非表示）
- Output files are saved in project directory (not `/tmp`) to share between WSL sessions. These files (`.codex-*.md`, `.codex-*.txt`) are explicitly unstaged after `git add -A` to ensure they don't appear in review diffs
- Completion marker `=== CODEX_DONE ===` is appended to output file
- Use `cat file | codex exec -` format to pass prompts (avoids escaping issues)
- Each Codex call is independent (no session state between calls)
- **Important**: Stage changes with `git add -A` before review so Codex can see new files (ensures visibility regardless of file discovery method)
- **Multi-turn exchange**: Use `next_action: continue|stop` to control exchange flow. Planning exchange max iterations default is 3.
- **Review iteration**: Enabled by default (`review.enabled: true`). Max iterations default is 5 (higher than exchange because goal is clear and diff is small).
- **Independent settings**: `exchange.*` and `review.*` are completely independent (no inheritance). Each can be configured separately.
