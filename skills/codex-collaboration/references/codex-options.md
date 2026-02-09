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

**Note**: Use project directory (`.codex-output.txt`) instead of `/tmp` to share between WSL sessions. These temporary files are excluded via `.gitignore` (see project root).

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

codex exec -s read-only - < prompt.txt
```

### Stdin Input

Read prompt from stdin using `-` argument:

```bash
# Redirect from file (recommended)
codex exec -s read-only - < prompt.txt

# Pipe from echo (may not work reliably with all codex versions)
echo "Your prompt" | codex exec -s read-only -
```

**Note**: The redirect format (`codex exec - < file`) is preferred over pipe format (`cat file | codex exec -`) for reliability.

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

## Running with Helper Functions

The recommended way to run `codex exec` within codex-collab is via the helper functions in `scripts/codex-helpers.sh`:

```bash
export CODEX_SKILL_CONTEXT=1
source scripts/codex-helpers.sh
PROMPT_FILE=$(codex_write_prompt "$PROMPT_CONTENT" "plan")
OUTPUT_FILE="$(codex_tmp_path 'codex-output.md')"
codex_run_exec "$PROMPT_FILE" "$OUTPUT_FILE" "read-only" "o4-mini"
```

### Helper Functions

| Function | Purpose |
|----------|---------|
| `codex_write_prompt(content, prefix)` | Write prompt to temp file, return path |
| `codex_run_exec(prompt, output, sandbox, model)` | Run codex exec with full I/O handling |
| `codex_build_exec_command(prompt, sandbox, model)` | Build command string (for eval) |
| `codex_strip_ansi(text)` | Remove ANSI escape codes from output |

### Key Points

- **Blocking execution**: `codex exec` blocks until completion, no polling needed
- **ANSI stripping**: Output may contain ANSI escape codes; `codex_run_exec` handles this automatically
- **Stdin input**: Use `cat file | codex exec -` format to avoid escaping issues
- **Timeout**: Bash tool has max 600s (10 minutes) timeout; set `codex.wait_timeout` accordingly

## Error Handling

### Common Errors

| Error | Cause | Resolution |
|-------|-------|------------|
| command not found | Codex CLI not installed | Install Codex CLI or add to PATH |
| Timeout | Complex operation | Simplify prompt or increase `codex.wait_timeout` |
| Model unavailable | API issues | Try different model or retry |
| API error | Rate limit or auth issue | Check API key and quota |

### Timeout Considerations

For long operations, consider:
- Breaking task into smaller prompts
- Using simpler model for initial pass
- Providing more specific context to reduce thinking time
