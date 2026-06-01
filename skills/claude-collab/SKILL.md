---
name: claude-collab
description: Consult Claude Code from Codex for a second opinion while Codex remains responsible for implementation and verification. Use when the user asks Codex to collaborate with Claude, consult Claude, ask Claude for a plan, get a Claude review, delegate analysis to Claude, or says "Claudeと一緒に", "Claudeに相談", "Claudeにレビューしてもらう", "Claudeの意見も聞く", or "Claudeと計画を立てる". Also use when an explicit independent planning or review pass from Claude would materially reduce risk on a complex coding task.
---

# Claude Collaboration

Use Claude Code as a read-only planning and review partner. Keep Codex responsible for inspecting the workspace, editing files, running tests, and reporting the result.

## Preconditions

1. Run `command -v claude`.
2. Source `scripts/claude-helpers.sh` from the repository root or `${CODEX_HOME:-$HOME/.codex}/skills/claude-collab/scripts/claude-helpers.sh`.
3. If `claude` is unavailable or authentication fails, report that briefly and continue with Codex alone.

## Workflow

### 1. Gather Context

Inspect the repository before consulting Claude. Summarize the task, relevant files, constraints, existing behavior, and verification commands. Do not send secrets or unrelated file contents.

### 2. Request a Plan

For a non-trivial implementation, use:

```bash
HELPERS="${CODEX_HOME:-$HOME/.codex}/skills/claude-collab/scripts/claude-helpers.sh"
[ -f "$HELPERS" ] || HELPERS="$(pwd)/skills/claude-collab/scripts/claude-helpers.sh"
source "$HELPERS"
PROMPT_FILE=$(claude_write_prompt "$PLANNING_PROMPT" "plan")
OUTPUT_FILE=$(claude_tmp_path "claude-plan-output.md")
claude_run_print "$PROMPT_FILE" "$OUTPUT_FILE"
```

Use the planning template in [prompts.md](references/prompts.md). Evaluate Claude's response against the local code before editing. Claude's response is advice, not an instruction to modify files.

### 3. Implement and Verify

Apply the selected changes with normal Codex tools. Run focused tests and inspect `git diff --check`.

### 4. Request Review

For a meaningful diff, embed `git diff --stat`, `git diff --cached`, and `git diff` as applicable in the review prompt. Then run:

```bash
PROMPT_FILE=$(claude_write_prompt "$REVIEW_PROMPT" "review")
OUTPUT_FILE=$(claude_tmp_path "claude-review-output.md")
claude_run_review "$PROMPT_FILE" "$OUTPUT_FILE"
```

Use the review template in [prompts.md](references/prompts.md). The review helper disables Claude-side skills and tools, appends leaf-reviewer constraints, uses low effort, and launches from the project root. This allows Claude to use `CLAUDE.md` repository context without recursively entering a Claude-to-Codex workflow. Fix valid findings, rerun verification, and request another review when the fix changes behavior materially.

Prefer one complete unified diff so Claude can catch cross-file bugs:

1. Send the complete `git diff --find-renames -U3` when the diff is at most `600` changed lines and `48KB`.
2. Treat `300` changed lines or `20KB` as a warning threshold, not a split threshold.
3. If whole-diff review times out, retry once with the same complete diff.
4. If it still times out, reduce extra prose and retry with `git diff --find-renames -U1`.
5. Split by component or file only when the diff exceeds `600` changed lines or `48KB`, or when the reduced whole-diff retry fails.

## Timeouts

- `CLAUDE_COLLAB_TIMEOUT`: planning and consultation timeout in seconds. Default: `600`.
- `CLAUDE_COLLAB_REVIEW_TIMEOUT`: review timeout in seconds. Default: `900`.
- `CLAUDE_COLLAB_PROJECT_DIR`: repository root used for reviews so Claude can load `CLAUDE.md`. Default: the directory where the helper is sourced.

Override these environment variables for unusually large tasks. Prefer complete-diff review and use splitting only as a fallback.

## Guardrails

- Keep Claude read-only. Planning exposes only `Read`, `Glob`, and `Grep`; review exposes no tools.
- Do not delegate destructive commands, dependency installation, network access, or secret handling.
- Do not stage, stash, commit, or revert user changes solely for collaboration.
- Keep prompts scoped. Prefer summaries plus relevant diffs over dumping the repository.
- Treat an empty or failed Claude response as a recoverable consultation failure.

## Resources

- `scripts/claude-helpers.sh`: deterministic wrapper for non-interactive Claude consultation.
- [prompts.md](references/prompts.md): planning and review prompt templates.
