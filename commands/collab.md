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
- Extract YAML frontmatter for: model, sandbox
- Apply settings priority: command args > project settings > defaults

**Default settings:**
- model: (Codex default)
- sandbox: read-only

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

### Step 5: Read and Validate Plan

Once completion is detected:

1. Read the output file: `cat "$CODEX_OUTPUT"`
2. Parse the plan from Codex's response
3. Validate for completeness:
   - [ ] Files to modify are clearly listed
   - [ ] Steps are specific and actionable
   - [ ] Risks are identified

Present the plan to the user and wait for confirmation before implementing.

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

**If CONDITIONAL:**
Apply suggested improvements, then complete

**If FAIL:**
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
- Output files are saved in project directory (not `/tmp`) to share between WSL sessions
- Completion marker `=== CODEX_DONE ===` is appended to output file
- Use `cat file | codex exec -` format to pass prompts (avoids escaping issues)
- Each Codex call is independent (no session state between calls)
- **Important**: Stage changes with `git add -A` before review so Codex can see new files (ensures visibility regardless of file discovery method)
