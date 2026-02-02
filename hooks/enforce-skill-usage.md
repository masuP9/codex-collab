---
name: enforce-skill-usage
description: Enforce using skills instead of direct Bash execution for codex-collab operations
event: PreToolUse
match_tool: Bash
type: prompt
---

# Codex-Collab Skill Usage Enforcement

You are about to execute a Bash command. Before proceeding, check if this command involves codex-collab helper functions.

## Skill Context Detection

**IMPORTANT**: First check if we are currently executing within a skill context.

The **primary and most reliable** method is checking for the `CODEX_SKILL_CONTEXT` environment variable in the command text.

**How to detect skill context (in order of reliability):**

1. **Environment variable (RELIABLE)**: The command includes `export CODEX_SKILL_CONTEXT=1`
   - All `/collab-codex` and `/strong-inference` commands set this at the beginning
   - This is the definitive signal that the command is running in skill context

2. **Heuristic (less reliable)**: You are currently processing a `/collab-codex` or `/strong-inference` command
   - Note: This may not be reliably accessible to the hook depending on platform implementation

**If skill context is detected**: Allow all Bash commands to proceed without blocking.

## Detection Patterns (only when NOT in skill context)

Check if the command contains any of these patterns using word-boundary matching:

1. **Helper function calls**: `\bcodex_[A-Za-z0-9_]+\b`
   - Matches: `codex_find_pane`, `codex_send_prompt`, `codex_wait_completion`, etc.
   - Does NOT match: variable names like `my_codex_var` or strings in comments

2. **Sourcing helpers (direct filename)**: `\bsource\b.*codex-helpers\.sh` or `\.\s+.*codex-helpers\.sh`
   - Matches: `source /path/to/codex-helpers.sh`, `. ./scripts/codex-helpers.sh`
   - Note: Does NOT match indirect references like `source "$HELPERS"` where HELPERS is a variable
   - This is a limitation; indirect sourcing may slip through

3. **Helper variable reference**: `\$HELPERS.*codex-helpers` or `HELPERS=.*codex-helpers`
   - Catches variable definitions and usages pointing to codex-helpers.sh

4. **Codex-collab variables**: `\bCODEX_PANE\b`, `\bCODEX_PROMPT\b`, `\bATTACHED_PANE\b`
   - Only when used as variable names

5. **Tmux Codex operations**: `tmux.*-t.*\$CODEX_PANE` or `tmux.*codex-pane`
   - Targeting Codex-specific panes

## If Patterns Detected (and NOT in skill context)

1. **BLOCK** this Bash execution
2. **Inform the user** that codex-collab operations should use skills
3. **Suggest** the appropriate skill:
   - For starting collaboration: `/collab-codex [task]`
   - For investigating problems: `/strong-inference [problem]`

## If No Patterns Detected OR In Skill Context

Allow the Bash command to proceed normally without any output.

## Response Format

**If blocking** (patterns detected AND not in skill context):
```
This Bash command appears to use codex-collab helper functions directly.

## Why This Is Blocked

Executing codex-collab commands outside a skill context triggers Claude Code's normal
safety checks, which require user approval for each command. Skills provide pre-authorized
permissions that avoid this friction.

## How to Proceed

Use the appropriate skill instead:

- `/collab-codex [task]` - Start a new collaboration workflow
- `/strong-inference [problem]` - Investigate a problem with competing hypotheses

## More Information

For full documentation on Bash usage rules, skill context detection, and troubleshooting:
See `docs/bash-usage.md` in the codex-collab plugin directory.
```

**If allowing**: Do not output anything, just allow the command to proceed.
