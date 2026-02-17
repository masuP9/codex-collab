---
name: enforce-skill-usage
description: Enforce using skills instead of direct Bash execution for codex-collab operations
---

# Codex-Collab Skill Usage Enforcement

> **Implementation**: This hook is implemented as a command-type hook (`hooks/enforce-skill-usage.sh`).
> The shell script works in both foreground and background agents (no LLM required).
> See `plugin.json` for the hook registration.

This document describes the detection logic used by `enforce-skill-usage.sh` to block direct Bash execution of codex-collab operations.

## Skill Context Detection

**IMPORTANT**: First check if we are currently executing within a skill context.

The **primary and most reliable** method is checking for the `CODEX_SKILL_CONTEXT` environment variable in the command text.

**How to detect skill context (in order of reliability):**

1. **Environment variable (RELIABLE)**: The command includes `export CODEX_SKILL_CONTEXT=1`
   - All `/codex-collab`, `/strong-inference`, and `/devils-advocate` commands set this at the beginning
   - This is the definitive signal that the command is running in skill context

2. **Heuristic (less reliable)**: You are currently processing a `/codex-collab`, `/strong-inference`, or `/devils-advocate` command
   - Note: This may not be reliably accessible to the hook depending on platform implementation

**If skill context is detected**: Allow all Bash commands to proceed without blocking.

## Detection Patterns (only when NOT in skill context)

Check if the command contains any of these patterns using word-boundary matching:

1. **Helper function calls**: `\bcodex_[A-Za-z0-9_]+\b`
   - Matches: `codex_run_exec`, `codex_build_exec_command`, `codex_write_prompt`, etc.
   - Does NOT match: variable names like `my_codex_var` or strings in comments

2. **Sourcing helpers (direct filename)**: `\bsource\b.*codex-helpers\.sh` or `\.\s+.*codex-helpers\.sh`
   - Matches: `source /path/to/codex-helpers.sh`, `. ./scripts/codex-helpers.sh`
   - Note: Does NOT match indirect references like `source "$HELPERS"` where HELPERS is a variable
   - This is a limitation; indirect sourcing may slip through

3. **Helper variable reference**: `\$HELPERS.*codex-helpers` or `HELPERS=.*codex-helpers`
   - Catches variable definitions and usages pointing to codex-helpers.sh

4. **Codex-collab variables**: `\bCODEX_PROMPT\b`
   - Only when used as variable names

## If Patterns Detected (and NOT in skill context)

1. **BLOCK** this Bash execution
2. **Inform the user** that codex-collab operations should use skills
3. **Suggest** the appropriate skill:
   - For starting collaboration: `/codex-collab [task]`
   - For investigating problems: `/strong-inference [problem]`
   - For stress-testing designs: `/devils-advocate [proposal]`

## If No Patterns Detected OR In Skill Context

Allow the Bash command to proceed normally without any output.

## Response Format

**If blocking** (exit 2, patterns detected AND not in skill context):
```
This Bash command uses codex-collab helper functions directly.

Use the appropriate skill instead:
- /codex-collab [task] - Start collaboration
- /strong-inference [problem] - Investigate problems
- /devils-advocate [proposal] - Stress-test designs

See docs/bash-usage.md for details.
```

**If allowing** (exit 0): No output, command proceeds normally.
