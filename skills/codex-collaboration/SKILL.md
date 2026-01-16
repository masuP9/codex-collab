---
name: Codex Collaboration
description: This skill should be used when the user asks to "collaborate with Codex", "use Codex for planning", "get Codex review", "delegate to Codex", "Codexと協調", "Codexにレビューを依頼", "Codexに計画を作成させたい", or mentions coordinating tasks between Claude Code and Codex CLI.
---

# Codex Collaboration Skill

Coordinate tasks between Claude Code and OpenAI Codex CLI using a review-based workflow where Codex handles planning and review while Claude Code handles implementation.

## Overview

This skill enables effective collaboration between two AI systems:
- **Codex**: Planning, code review, architectural decisions
- **Claude Code**: Implementation, file operations, testing

The primary pattern is "Review Type" where Codex creates plans and reviews implementation, while Claude Code executes the actual work.

**Key Feature**: WSL環境では、Codexは新しいペインで起動するため、リアルタイムで出力を確認できます。完了は自動検知されます。その他の環境では現在のターミナルで実行されます。

## Prerequisites

Before starting collaboration:
1. Verify `codex` CLI is available: `which codex` or `codex --version`
2. Verify terminal launcher is available:
   - WSL: `which wt.exe` (Windows Terminal)
   - Linux: `which gnome-terminal` or `which xterm`
3. Check for project settings in `.claude/codex-collab.local.md`
4. If Codex CLI unavailable, inform user and proceed with Claude-only mode

## Workflow: Review Type (Default)

### Phase 1: Task Analysis

When receiving a task for collaboration:

1. Parse the task description to identify:
   - Core objective
   - Affected files/components
   - Complexity level
   - Required context

2. Gather relevant context:
   - Read related files
   - Check existing tests
   - Review recent changes

### Phase 2: Launch Codex for Planning (New Pane)

1. Prepare files in project directory:
```bash
CODEX_OUTPUT="$(pwd)/.codex-plan-output.md"
CODEX_PROMPT="$(pwd)/.codex-plan-prompt.txt"
rm -f "$CODEX_OUTPUT"

cat > "$CODEX_PROMPT" << 'EOF'
[Planning prompt content]
EOF
```

2. Launch Codex in a new pane:

**WSL / Windows Terminal:**
```bash
wt.exe -w -1 -d "$(pwd)" -p Ubuntu wsl.exe zsh -i -l -c "cat [PROMPT_FILE] | codex exec -s read-only - 2>&1 | tee [OUTPUT_FILE] && echo '=== CODEX_DONE ===' >> [OUTPUT_FILE]"
```

3. Auto-detect completion:
```bash
for i in {1..120}; do
  if grep -q "=== CODEX_DONE ===" "$CODEX_OUTPUT" 2>/dev/null; then
    echo "Codex completed after ${i}s"
    break
  fi
  sleep 1
done
```

4. Read results from output file

### Phase 3: Implement Based on Plan

After receiving Codex's plan:

1. Validate the plan is reasonable
2. Present plan to user for confirmation
3. Execute implementation step by step
4. Track changes made

### Phase 4: Launch Codex for Review (New Pane)

After implementation:

1. Prepare review files:
```bash
CODEX_REVIEW="$(pwd)/.codex-review-output.md"
REVIEW_PROMPT="$(pwd)/.codex-review-prompt.txt"
rm -f "$CODEX_REVIEW"

cat > "$REVIEW_PROMPT" << 'EOF'
[Review prompt with original plan and diff summary]
EOF
```

2. Launch Codex and auto-detect completion:
```bash
wt.exe -w -1 -d "$(pwd)" -p Ubuntu wsl.exe zsh -i -l -c "cat [REVIEW_PROMPT] | codex exec -s read-only - 2>&1 | tee [CODEX_REVIEW] && echo '=== CODEX_DONE ===' >> [CODEX_REVIEW]"

for i in {1..120}; do
  if grep -q "=== CODEX_DONE ===" "$CODEX_REVIEW" 2>/dev/null; then
    break
  fi
  sleep 1
done
```

3. Read and process review results

The review prompt must request:
- Design alignment check
- Bug/vulnerability detection
- Improvement suggestions
- Verdict: Pass / Fail / Conditional

### Phase 5: Handle Review Result

Based on review verdict:

**Pass**: Report completion to user

**Conditional**:
1. Apply suggested improvements
2. Re-request review if significant changes

**Fail**:
1. Analyze failure reasons
2. Either fix issues or escalate to user

## Settings and Configuration

### Reading Project Settings

Check for `.claude/codex-collab.local.md` in project root:

```markdown
---
model: o4-mini
sandbox: read-only
---

# Project-specific instructions
```

Parse YAML frontmatter for:
- `model`: Codex model to use
- `sandbox`: read-only | workspace-write | danger-full-access

### Settings Priority

Apply settings in this order (later overrides earlier):

1. **Safe defaults**: sandbox=read-only
2. **Global settings**: ~/.claude/codex-collab.local.md
3. **Project settings**: .claude/codex-collab.local.md
4. **Command arguments**: Explicit user request

### Safe Defaults

Always start with secure defaults:
- `sandbox: read-only` - Codex cannot modify files

## Quality Gates

### Plan Quality Criteria

A valid plan from Codex must include:
- [ ] Clear list of files to modify
- [ ] Specific changes for each file
- [ ] Rationale for approach
- [ ] Identified risks or concerns
- [ ] Test coverage considerations

If plan is incomplete, request clarification from Codex.

### Review Acceptance Criteria

Accept review as "Pass" only when:
- [ ] All changed files reviewed
- [ ] No critical bugs identified
- [ ] Security concerns addressed
- [ ] Design aligns with original plan
- [ ] Test coverage adequate

## Launching Codex in New Pane

### WSL / Windows Terminal (Pane - Default)

```bash
# Output files in project directory (shared between WSL sessions)
CODEX_OUTPUT="$(pwd)/.codex-output.md"
CODEX_PROMPT="$(pwd)/.codex-prompt.txt"
rm -f "$CODEX_OUTPUT"

# Write prompt to file
cat > "$CODEX_PROMPT" << 'EOF'
Your prompt here
EOF

# Launch in new pane (use cat | codex exec - format)
wt.exe -w -1 -d "$(pwd)" -p Ubuntu wsl.exe zsh -i -l -c "cat [PROMPT_FILE] | codex exec -s read-only - 2>&1 | tee [OUTPUT_FILE] && echo '=== CODEX_DONE ===' >> [OUTPUT_FILE]"

# Auto-detect completion (poll for marker)
for i in {1..120}; do
  if grep -q "=== CODEX_DONE ===" "$CODEX_OUTPUT" 2>/dev/null; then
    echo "Codex completed after ${i}s"
    break
  fi
  sleep 1
done
```

### Native Linux (gnome-terminal)

```bash
CODEX_OUTPUT="$(pwd)/.codex-output.md"
CODEX_PROMPT="$(pwd)/.codex-prompt.txt"
rm -f "$CODEX_OUTPUT"

gnome-terminal -- bash -c "cat $CODEX_PROMPT | codex exec -s read-only - 2>&1 | tee $CODEX_OUTPUT && echo '=== CODEX_DONE ===' >> $CODEX_OUTPUT"
```

### Native Linux (xterm)

```bash
CODEX_OUTPUT="$(pwd)/.codex-output.md"
CODEX_PROMPT="$(pwd)/.codex-prompt.txt"
rm -f "$CODEX_OUTPUT"

xterm -e bash -c "cat $CODEX_PROMPT | codex exec -s read-only - 2>&1 | tee $CODEX_OUTPUT && echo '=== CODEX_DONE ===' >> $CODEX_OUTPUT"
```

### Codex CLI Options

- `-m, --model <model>` - Specify model (e.g., o4-mini, o3)
- `-s, --sandbox <mode>` - read-only | workspace-write | danger-full-access
- `-C, --cd <dir>` - Working directory
- `--full-auto` - Automatic execution mode
- `-` - Read prompt from stdin

### Important Notes

- Each `codex exec` call is stateless (no conversation history between calls)
- Include all necessary context in each prompt
- Use `-s read-only` for planning/review tasks (Codex won't modify files)
- **Project directory**: Output files saved in project directory (not `/tmp`) to share between WSL sessions
- **Completion marker**: `=== CODEX_DONE ===` appended to output file for auto-detection
- **Stdin input**: Use `cat file | codex exec -` format to avoid escaping issues

## Error Handling

### Terminal Launcher Unavailable

If `wt.exe` is not available (non-WSL/Linux環境):
1. Fall back to running `codex exec` in current terminal
2. Inform user: "WSL環境ではないため、現在のターミナルでCodexを実行します。完了まで出力は表示されません。"
3. 出力はファイルに保存されるので、完了後に結果を確認できます

### CLI Unavailable

If `codex` command is not found:
1. Inform user: "Codex CLI is not installed or not in PATH"
2. Offer to proceed with Claude-only mode
3. Continue with standard Claude Code workflow

### Codex Timeout or Error

If Codex returns error:
1. Check error message in output file
2. Retry once with simplified prompt
3. If still failing, proceed manually and inform user

### Auto-detection Timeout

If 120 seconds pass without detecting completion marker:
1. Ask user if Codex is still running
2. Offer to extend wait time or read partial output
3. Check output file manually: `cat "$CODEX_OUTPUT"`

## Additional Resources

### Templates

Prompt templates for Codex communication:
- **`templates/planning-prompt.md`** - Template for requesting plans
- **`templates/review-prompt.md`** - Template for requesting reviews

### References

Detailed documentation:
- **`references/codex-options.md`** - Codex CLI configuration options
- **`references/workflow-patterns.md`** - Alternative workflow patterns
