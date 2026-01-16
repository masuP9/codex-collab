# Codex CLI Configuration Options

Reference documentation for `codex exec` command parameters.

## codex exec Command

Execute a single prompt with Codex CLI.

### Basic Syntax

```bash
codex exec [OPTIONS] [PROMPT]
```

### Options

| Option | Short | Description |
|--------|-------|-------------|
| `--model <MODEL>` | `-m` | Model the agent should use |
| `--sandbox <MODE>` | `-s` | Sandbox policy for shell commands |
| `--cd <DIR>` | `-C` | Working directory |
| `--config <key=value>` | `-c` | Override config values |
| `--profile <PROFILE>` | `-p` | Configuration profile from config.toml |
| `--image <FILE>` | `-i` | Attach image(s) to the prompt |
| `--full-auto` | | Automatic execution mode (sandbox workspace-write) |
| `--output-last-message <FILE>` | `-o` | Write last message to file |
| `--json` | | Print events as JSONL |

### Sandbox Modes (`-s, --sandbox`)

| Mode | Description | Use Case |
|------|-------------|----------|
| `read-only` | Cannot modify files | Safe for planning/review |
| `workspace-write` | Can write to workspace | For implementation tasks |
| `danger-full-access` | Full system access | Use with extreme caution |

**Default for collaboration**: `read-only` (Codex plans/reviews, Claude implements)

### Full Auto Mode

`--full-auto` is a convenience alias that sets:
- Sandbox: `workspace-write`
- Automatic approval for most operations

Use this when you want Codex to execute without manual approvals.

### Config Overrides (`-c, --config`)

Override settings from `~/.codex/config.toml`:

```bash
# Set model
codex exec -c model="o3" "prompt"

# Set sandbox permissions
codex exec -c 'sandbox_permissions=["disk-full-read-access"]' "prompt"

# Multiple overrides
codex exec -c model="o4-mini" -c 'features.stream=true' "prompt"
```

## Model Selection

### Available Models

Common models (subject to OpenAI availability):
- `o3` - Most capable, higher cost
- `o4-mini` - Balanced performance/cost
- Default varies by Codex installation

### Selection Criteria

| Task Type | Recommended Model |
|-----------|-------------------|
| Complex planning | o3 |
| Quick review | o4-mini |
| Architectural decisions | o3 |
| Simple validation | o4-mini |

## Configuration Hierarchy

Settings are applied in order (later overrides earlier):

1. Codex installation defaults
2. `~/.codex/config.toml` (user global)
3. Plugin safe defaults
4. Project `.claude/codex-collab.local.md`
5. Explicit command arguments (`-c`, `-m`, `-s`, etc.)

## Example Commands

### Planning Request

```bash
codex exec \
  -s read-only \
  "Create implementation plan for adding user authentication"
```

### Review Request

```bash
codex exec \
  -s read-only \
  "Review the following changes:

## Changes Made
- Modified src/auth.ts: Added login function
- Created src/middleware/auth.ts: JWT validation

## Diff Summary
[diff content here]

Provide a code review with verdict (PASS/CONDITIONAL/FAIL)."
```

### With Specific Model

```bash
codex exec \
  -m o4-mini \
  -s read-only \
  "Quick validation: Is this function safe? [code here]"
```

### Full Auto Execution

```bash
codex exec --full-auto "Fix the linting errors in src/"
```

### Save Output to File

```bash
codex exec \
  -s read-only \
  -o .codex-output.txt \
  "Analyze this codebase structure"
```

**Note**: Use project directory (`.codex-output.txt`) instead of `/tmp` to share between WSL sessions.

## Important Notes

### Stateless Execution

Each `codex exec` call is **completely independent**:
- No conversation history between calls
- No session state is maintained
- Each call must include all necessary context

This means:
- Include relevant code/context in each prompt
- For review, include both the original plan and the changes made
- Cannot reference "previous" conversations

### Long Prompts

For long prompts, write to a file and use stdin pipe format (recommended to avoid escaping issues):

```bash
cat > prompt.txt << 'EOF'
Your long prompt here
with multiple lines
and code blocks
EOF

cat prompt.txt | codex exec -s read-only -
```

### Stdin Input

Read prompt from stdin using `-` argument:

```bash
echo "Your prompt" | codex exec -s read-only -

cat prompt.txt | codex exec -s read-only -
```

**Note**: The stdin pipe format (`cat file | codex exec -`) is preferred over `$(cat file)` to avoid escaping issues, especially when launching Codex through multiple shell layers (e.g., wt.exe → wsl.exe → zsh).

## Subcommands

### codex exec resume

Resume a previous session:

```bash
codex exec resume --last  # Resume most recent session
codex exec resume <session-id>  # Resume specific session
```

### codex exec review

Run a code review against the current repository:

```bash
codex exec review
```

## Launching in New Pane

To see Codex output in real-time, launch it in a separate pane. Completion is auto-detected via a marker.

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
wt.exe -w 0 sp -d "$(pwd)" -V -p Ubuntu wsl.exe zsh -i -l -c "cat [PROMPT_FILE] | codex exec -s read-only - 2>&1 | tee [OUTPUT_FILE] && echo '=== CODEX_DONE ===' >> [OUTPUT_FILE]"

# Auto-detect completion (poll for marker)
for i in {1..120}; do
  if grep -q "=== CODEX_DONE ===" "$CODEX_OUTPUT" 2>/dev/null; then
    echo "Codex completed after ${i}s"
    break
  fi
  sleep 1
done
```

**Options:**
- `-w 0` - Use current window
- `sp` - Split pane
- `-d "$(pwd)"` - Current directory (WSL path)
- `-V` - Vertical split (left-right, default)
- `-H` - Horizontal split (top-bottom)
- `-p <profile>` - Terminal profile (e.g., `Ubuntu`)
- `nt` - New tab (alternative)

### WSL / Windows Terminal (Tab - Alternative)

```bash
wt.exe -w 0 nt wsl.exe zsh -i -l -c "cat [PROMPT_FILE] | codex exec -s read-only - 2>&1 | tee [OUTPUT_FILE] && echo '=== CODEX_DONE ===' >> [OUTPUT_FILE]"
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

### macOS (Terminal.app)

```bash
CODEX_OUTPUT="$(pwd)/.codex-output.md"
CODEX_PROMPT="$(pwd)/.codex-prompt.txt"
rm -f "$CODEX_OUTPUT"

osascript -e "tell app \"Terminal\" to do script \"cat $CODEX_PROMPT | codex exec -s read-only - 2>&1 | tee $CODEX_OUTPUT && echo '=== CODEX_DONE ===' >> $CODEX_OUTPUT\""
```

### Key Points

- **Project directory**: Output files saved in project directory (not `/tmp`) to share between WSL sessions
- **Stdin input**: Use `cat file | codex exec -` format to avoid escaping issues
- **Completion marker**: `=== CODEX_DONE ===` appended to output file for auto-detection
- User can watch Codex in real-time in the new pane
- Claude Code auto-detects completion and reads results from output file

## Error Handling

### Common Errors

| Error | Cause | Resolution |
|-------|-------|------------|
| command not found | Codex CLI not installed | Install Codex CLI or add to PATH |
| wt.exe not found | Not in WSL or Windows Terminal not installed | Use alternative terminal launcher |
| Timeout | Complex operation | Simplify prompt |
| Model unavailable | API issues | Try different model or retry |
| API error | Rate limit or auth issue | Check API key and quota |

### Timeout Considerations

For long operations, consider:
- Breaking task into smaller prompts
- Using simpler model for initial pass
- Providing more specific context to reduce thinking time
