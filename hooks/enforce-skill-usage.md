---
name: enforce-skill-usage
description: Soft guard against accidental direct use of codex-collab side-effect helpers
---

# Codex-Collab Skill Usage Enforcement

> **Implementation**: This hook is implemented as a command-type hook (`hooks/enforce-skill-usage.sh`).
> The shell script works in both foreground and background agents (no LLM required).
> See `plugin.json` for the hook registration.

This document describes the detection logic used by `enforce-skill-usage.sh` to soft-guard direct Bash execution of codex-collab side-effect helpers.

**Purpose**: This is a soft guard against accidental direct use of internal APIs, not a security boundary. Detection misses (false negatives) are intentionally accepted in exchange for reduced false-positive rate and lower maintenance cost.

## Skill Context Detection

**IMPORTANT**: First check if we are currently executing within a skill context.

The **primary and most reliable** method is checking for the `CODEX_SKILL_CONTEXT` environment variable in the command text.

**How to detect skill context:**

1. **Line-start export (RELIABLE)**: The command contains a line that starts with `export CODEX_SKILL_CONTEXT=1` (optional leading whitespace allowed)
   - All `/codex-collab`, `/strong-inference`, and `/devils-advocate` commands set this at the beginning of each Bash block
   - This is the definitive signal that the command is running in skill context
   - **Substring mentions are NOT honored**: `echo "CODEX_SKILL_CONTEXT=1"` or a value embedded inside a quoted string does not bypass the guard

**If skill context is detected**: Allow all Bash commands to proceed without blocking.

## Detection Patterns (only when NOT in skill context)

Check if the command matches the following pattern at an execution position (line start, after `;` `&` `|`, inside `$(...)` or backticks):

**Side-effect helper calls**: `(^|[;&|]|\$\(|`)[[:space:]]*codex_(run_exec|run_review|save_session_state|save_thread)\b`

Protected functions (external execution and session-state writes):
- `codex_run_exec` — runs external codex CLI
- `codex_run_review` — runs codex review subprocess
- `codex_save_session_state` — writes session state to filesystem
- `codex_save_thread` — writes named thread to filesystem

**Intentionally NOT guarded** (not side-effect helpers):
- Pure transforms: `codex_strip_ansi`, `codex_infer_verdict`, `codex_extract_review_findings`, `codex_get_field`, etc.
- Read-only helpers: `codex_load_session_state`, `codex_load_thread`, `codex_tmp_path`, etc.
- Speculative patterns: `source codex-helpers.sh`, `HELPERS=...`, `CODEX_PROMPT` — removed to reduce false positives

## If Pattern Detected (and NOT in skill context)

1. **BLOCK** this Bash execution (exit 2)
2. **Inform the user** that this is a soft guard for side-effect helpers
3. **Suggest** the appropriate skill:
   - For starting collaboration: `/codex-collab [task]`
   - For investigating problems: `/strong-inference [problem]`
   - For stress-testing designs: `/devils-advocate [proposal]`
4. **Offer bypass** via `export CODEX_SKILL_CONTEXT=1; <command>` for intentional direct use

## If No Pattern Detected OR In Skill Context

Allow the Bash command to proceed normally without any output.

## Response Format

**If blocking** (exit 2, pattern detected AND not in skill context):
```
This command calls a codex-collab side-effect helper directly
(codex_run_exec / codex_run_review / codex_save_session_state / codex_save_thread).

This is a soft guard against accidental direct use of internal APIs,
not a security boundary. Preferred entry points:
- /codex-collab [task] - Start collaboration
- /strong-inference [problem] - Investigate problems
- /devils-advocate [proposal] - Stress-test designs

If you are doing this intentionally, start the line with:
  export CODEX_SKILL_CONTEXT=1; <your command>

See docs/bash-usage.md for details.
```

**If allowing** (exit 0): No output, command proceeds normally.
