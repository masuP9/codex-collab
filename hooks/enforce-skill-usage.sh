#!/usr/bin/env bash
# enforce-skill-usage.sh - PreToolUse command hook for codex-collab
#
# Enforces that codex-collab operations use skills instead of direct Bash.
# Type: command (works in both foreground and background agents)
#
# Protocol (Claude Code hook):
#   Input:  JSON via stdin with .tool_input.command
#   Output: exit 0 = allow, exit 2 = block (stderr shown to user)

# Require jq for JSON parsing; fail open if unavailable
command -v jq &>/dev/null || exit 0

# Read and extract command from tool input
COMMAND=$(jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -z "$COMMAND" ] && exit 0

# Skill context marker — allow everything
echo "$COMMAND" | grep -qF 'CODEX_SKILL_CONTEXT=1' && exit 0

# Check for codex-collab patterns
PATTERN='(^|[;&|]|\$\(|`)[[:space:]]*codex_[A-Za-z0-9_]+'
PATTERN="$PATTERN"'|\bsource\b.*codex-helpers\.sh'
PATTERN="$PATTERN"'|\.[ \t]+.*codex-helpers\.sh'
# shellcheck disable=SC2016 # $HELPERS is a literal grep pattern (single-quoted intentionally, not a variable)
PATTERN="$PATTERN"'|\$HELPERS.*codex-helpers'
PATTERN="$PATTERN"'|HELPERS=.*codex-helpers'
PATTERN="$PATTERN"'|\bCODEX_PROMPT\b'

if echo "$COMMAND" | grep -qE "$PATTERN"; then
  cat >&2 << 'MSG'
This Bash command uses codex-collab helper functions directly.

Use the appropriate skill instead:
- /codex-collab [task] - Start collaboration
- /strong-inference [problem] - Investigate problems
- /devils-advocate [proposal] - Stress-test designs

See docs/bash-usage.md for details.
MSG
  exit 2
fi

exit 0
