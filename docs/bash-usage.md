# Bash Usage Rules for codex-collab

This document explains the Bash usage rules enforced by the codex-collab plugin.

## Overview

The codex-collab plugin includes a PreToolUse hook that enforces skill-based execution of codex-collab operations. This ensures consistent behavior and avoids unnecessary approval prompts.

## Why Use Skills Instead of Direct Bash?

When you execute Bash commands through a skill (like `/codex-collab`), the commands run within the skill's permission scope (`allowed-tools: Bash`). This means:

- **No approval prompts**: Commands are pre-authorized by the skill definition
- **Consistent behavior**: The same command always works the same way
- **Better UX**: No repeated interruptions asking for permission

When you execute the same commands **outside** a skill context (directly in conversation), Claude Code's normal safety checks apply, which may require user approval for each command.

## Available Skills

| Skill | Purpose | Example |
|-------|---------|---------|
| `/codex-collab [task]` | Start a new collaboration workflow | `/codex-collab implement feature X` |
| `/strong-inference [problem]` | Investigate a problem with competing hypotheses | `/strong-inference APIが時々500エラーを返す` |
| `/devils-advocate [proposal]` | Stress-test a design or proposal | `/devils-advocate このキャッシュ設計を検証して` |

> **Note:** `strong-inference` と `devils-advocate` の使い分けについては、[README.md の使い分けガイド](../README.md#strong-inference-vs-devils-advocate-の使い分け)を参照してください。

## How Skill Context Detection Works

The PreToolUse hook (`hooks/enforce-skill-usage.sh`) detects skill context using the following methods. This hook uses `type: command` (shell script) so it works in both foreground and background agents.

### Primary Method (Reliable)

Check if the Bash command includes `export CODEX_SKILL_CONTEXT=1`.

All codex-collab skills set this environment variable at the beginning of their Bash blocks:

```bash
# Mark skill context for PreToolUse hook detection
export CODEX_SKILL_CONTEXT=1

# Source helpers with fallback chain
HELPERS=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh" ]; then
  HELPERS="${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh"
elif [ -d ~/.claude/plugins/cache/codex-collab ]; then
  HELPERS=$(ls -td ~/.claude/plugins/cache/codex-collab/codex-collab/*/scripts/codex-helpers.sh 2>/dev/null | head -1)
fi
[ -z "$HELPERS" ] || [ ! -f "$HELPERS" ] && HELPERS="$(pwd)/scripts/codex-helpers.sh"
[ -f "$HELPERS" ] && source "$HELPERS"
```

When this marker is present, all Bash commands are allowed without blocking.

### Note on jq Dependency

The hook script requires `jq` to parse the JSON input from Claude Code. If `jq` is not available, the hook fails open (allows all commands). This is acceptable since the hook is a quality-of-life feature, not a security control.

## Detection Patterns

When **not** in skill context, the hook checks for these patterns to identify codex-collab operations:

| Pattern | Description | Example | Limitation |
|---------|-------------|---------|------------|
| `\bcodex_[A-Za-z0-9_]+\b` | Helper function calls | `codex_run_exec` | - |
| `\bsource\b.*codex-helpers\.sh` or `\.\s+.*codex-helpers\.sh` | Direct path sourcing (source/dot) | `source ./scripts/codex-helpers.sh` | Indirect refs not detected |
| `\$HELPERS.*codex-helpers` or `HELPERS=.*codex-helpers` | Variable reference/definition | `HELPERS="./codex-helpers.sh"` | - |
| `\bCODEX_PROMPT\b` | codex-collab variables | `$CODEX_PROMPT` | - |

### Known Limitations

- **Indirect sourcing**: `source "$HELPERS"` where `HELPERS` is set elsewhere may not be detected
- **Pattern matching**: Uses word boundaries (`\b`) to avoid false positives, but edge cases may exist

## What Happens When Blocked

If you try to execute codex-collab operations outside a skill context, you'll see a message like:

```
This Bash command uses codex-collab helper functions directly.

Use the appropriate skill instead:
- /codex-collab [task] - Start collaboration
- /strong-inference [problem] - Investigate problems
- /devils-advocate [proposal] - Stress-test designs

See docs/bash-usage.md for details.
```

## Troubleshooting

### "Why am I being blocked?"

You're trying to execute codex-collab Bash commands directly instead of through a skill. Use one of the available skills listed above.

### "I need to run a custom command"

If you need to run custom commands that use codex-collab helpers:

1. **Recommended**: Create a new skill or modify an existing one
2. **Workaround**: Ensure your command includes `export CODEX_SKILL_CONTEXT=1` at the beginning

### "The hook is blocking legitimate commands"

The detection uses pattern matching which may occasionally have false positives. If you believe a command is incorrectly blocked:

1. Check if the command contains any of the detection patterns
2. Consider using a skill instead
3. Add `export CODEX_SKILL_CONTEXT=1` if appropriate

## For Plugin Developers

### Adding New Commands

When creating new commands that use codex-collab helpers, always include:

```bash
# Mark skill context for PreToolUse hook detection
export CODEX_SKILL_CONTEXT=1
```

This ensures the hook recognizes the command as running in skill context.

### Modifying Detection Patterns

Detection patterns are defined in `hooks/enforce-skill-usage.sh`. Modify with caution to avoid:
- False positives (blocking unrelated commands)
- False negatives (missing codex-collab commands)
