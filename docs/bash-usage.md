# Bash Usage Rules for codex-collab

This document explains the Bash usage rules enforced by the codex-collab plugin.

## Overview

The codex-collab plugin includes a PreToolUse hook that enforces skill-based execution of codex-collab operations. This ensures consistent behavior and avoids unnecessary approval prompts.

## Why Use Skills Instead of Direct Bash?

When you execute Bash commands through a skill (like `/collab-codex`), the commands run within the skill's permission scope (`allowed-tools: Bash`). This means:

- **No approval prompts**: Commands are pre-authorized by the skill definition
- **Consistent behavior**: The same command always works the same way
- **Better UX**: No repeated interruptions asking for permission

When you execute the same commands **outside** a skill context (directly in conversation), Claude Code's normal safety checks apply, which may require user approval for each command.

## Available Skills

| Skill | Purpose | Example |
|-------|---------|---------|
| `/collab-codex [task]` | Start a new collaboration workflow | `/collab-codex implement feature X` |
| `/strong-inference [problem]` | Investigate a problem with competing hypotheses | `/strong-inference APIが時々500エラーを返す` |

## How Skill Context Detection Works

The PreToolUse hook (`hooks/enforce-skill-usage.md`) detects skill context using the following methods:

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

### Heuristic Method (Less Reliable)

The hook may also check if you're currently processing a `/collab-codex` or `/strong-inference` command based on conversation context. However, this is not always reliably accessible depending on platform implementation.

## Detection Patterns

When **not** in skill context, the hook checks for these patterns to identify codex-collab operations:

| Pattern | Description | Example | Limitation |
|---------|-------------|---------|------------|
| `\bcodex_[A-Za-z0-9_]+\b` | Helper function calls | `codex_find_pane` | - |
| `\bsource\b.*codex-helpers\.sh` | Direct path sourcing | `source ./scripts/codex-helpers.sh` | Indirect refs not detected |
| `HELPERS=.*codex-helpers` | Variable definition | `HELPERS="./codex-helpers.sh"` | - |
| `\bCODEX_PANE\b`, `\bATTACHED_PANE\b` | codex-collab variables | `$CODEX_PANE` | - |

### Known Limitations

- **Indirect sourcing**: `source "$HELPERS"` where `HELPERS` is set elsewhere may not be detected
- **Pattern matching**: Uses word boundaries (`\b`) to avoid false positives, but edge cases may exist

## What Happens When Blocked

If you try to execute codex-collab operations outside a skill context, you'll see a message like:

```
This Bash command appears to use codex-collab helper functions directly.

To ensure consistent behavior and avoid unnecessary approval prompts, please use the appropriate skill instead:

- `/collab-codex [task]` - Start a new collaboration workflow
- `/collab-codex [task]` - Start a new collaboration workflow (reuses existing Codex pane if available)

Reason: Skill execution provides proper tool permissions and avoids repeated approval requests.

For more details, see: docs/bash-usage.md
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

Detection patterns are defined in `hooks/enforce-skill-usage.md`. Modify with caution to avoid:
- False positives (blocking unrelated commands)
- False negatives (missing codex-collab commands)
