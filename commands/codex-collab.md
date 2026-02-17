---
name: codex-collab
description: Start a collaborative task with Codex (default: codex-leads workflow)
argument-hint: [task description]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, AskUserQuestion, mcp__codex__codex, mcp__codex__codex-reply
---

# Codex Collaboration Workflow

Execute a collaborative workflow between Claude Code and Codex CLI.

**Workflow modes** (`workflow` setting):
- **codex-leads** (従来): Codex が計画・レビュー、Claude が実装
- **claude-leads** (新規): Claude が計画・レビュー、Codex が実装（workspace-write sandbox）
- **auto** (default): 常に codex-leads を選択（明示的に `claude-leads` を指定した場合のみ Claude 主導）

**Architecture**: MCP primary + Bash fallback のデュアルモード。MCP (`mcp__codex__codex`/`codex-reply`) はステートフルな会話を提供。MCP 未設定時は `codex exec` (Bash) にフォールバック。

## Task

$ARGUMENTS

## Workflow Instructions

### Step 0: Load Helper Functions

Source shared helper functions at the beginning of any bash block. **Always set `CODEX_SKILL_CONTEXT=1`** to indicate skill context for the PreToolUse hook:

```bash
# Mark skill context for PreToolUse hook detection
export CODEX_SKILL_CONTEXT=1

# Source helpers with robust fallback chain
# 1. Try CLAUDE_PLUGIN_ROOT if valid
# 2. Try Claude plugin cache (latest version)
# 3. Try current directory (for development)
HELPERS=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh" ]; then
  HELPERS="${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh"
elif [ -d ~/.claude/plugins/cache/codex-collab ]; then
  HELPERS=$(ls -td ~/.claude/plugins/cache/codex-collab/codex-collab/*/scripts/codex-helpers.sh 2>/dev/null | head -1)
fi
if [ -z "$HELPERS" ] || [ ! -f "$HELPERS" ]; then
  HELPERS="$(pwd)/scripts/codex-helpers.sh"
fi
if [ -f "$HELPERS" ]; then
  source "$HELPERS"
else
  echo "Error: codex-helpers.sh not found" >&2
  echo "Tried: CLAUDE_PLUGIN_ROOT, ~/.claude/plugins/cache, $(pwd)" >&2
fi
```

> **Note:** Helper functions are required for this workflow. The loader tries multiple locations: `CLAUDE_PLUGIN_ROOT`, Claude plugin cache, and current directory.
> **Important:** The `CODEX_SKILL_CONTEXT=1` export is required for the PreToolUse hook to recognize this as skill context and allow Bash execution without blocking.

### Step 0a: Determine Communication Mode (MCP vs Bash)

Determine whether to use MCP tools or Bash CLI for Codex communication.

**1. Probe MCP availability:**

Call `mcp__codex__codex` with a lightweight ping:
```
mcp__codex__codex(prompt: "ping", sandbox: "read-only")
```

- **Success** → MCP mode. Save the returned `threadId` to session state.
- **Failure** (tool not available, permission denied, error) → Bash mode (従来動作).

**2. Save session state:**

```bash
export CODEX_SKILL_CONTEXT=1

# Source helpers
HELPERS=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh" ]; then
  HELPERS="${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh"
elif [ -d ~/.claude/plugins/cache/codex-collab ]; then
  HELPERS=$(ls -td ~/.claude/plugins/cache/codex-collab/codex-collab/*/scripts/codex-helpers.sh 2>/dev/null | head -1)
fi
if [ -z "$HELPERS" ] || [ ! -f "$HELPERS" ]; then
  HELPERS="$(pwd)/scripts/codex-helpers.sh"
fi
[ -f "$HELPERS" ] && source "$HELPERS"

TASK_ID="collab-$$-$(date +%s)"
# MODE and THREAD_ID are set by the probe result above
# MODE="mcp" or "bash", THREAD_ID from probe response (empty for bash)
# Note: Save with defaults here. Workflow/sandbox are updated after Step 1 loads settings.
codex_save_session_state "$TASK_ID" "$MODE" "$THREAD_ID"
echo "Communication mode: $MODE (task_id: $TASK_ID)"
```

**MCP Fallback Strategy (error-type based):**
- `thread_not_found` / `auth_error` / `tool_not_available` → Switch to Bash fallback
- `timeout` / `transient_error` → Retry MCP (max 2 retries)
- 3 consecutive failures → Switch to Bash mode

> **Note:** MCP mode provides: stateful conversation (threadId), clean text (no ANSI), no file I/O for prompts, direct response reading (no bash parsing). Bash mode preserves all existing functionality as fallback.

### Step 1: Load Settings

Check for project-specific settings:
- Read `.claude/codex-collab.local.md` if it exists
- Extract YAML frontmatter for: model, sandbox, codex, exchange, review, **workflow** settings
- Apply settings priority: command args > project settings > defaults

**Default settings:**
- **workflow**: auto (options: auto, codex-leads, claude-leads; auto は常に codex-leads を選択)
- model: (Codex default)
- sandbox: read-only (codex-leads) / workspace-write (claude-leads)
- language: en (Codex response language)
- **Timeout** (codex.*):
  - codex.wait_timeout: 180 (seconds, max 600)
- **Planning exchange** (exchange.*, codex-leads only):
  - exchange.enabled: true
  - exchange.max_iterations: 3
  - exchange.user_confirm: on_important
  - exchange.history_mode: summarize
- **Review iteration** (review.*, codex-leads only):
  - review.enabled: true
  - review.max_iterations: 5
  - review.max_verdict_retries: 3 (retries when verdict is missing/unclear)
  - review.user_confirm: never
- **Claude-leads specific** (claude_leads.*):
  - claude_leads.sandbox: workspace-write (Codex 実装用 sandbox)
  - claude_leads.consult_codex: true (壁打ちフェーズを有効化)
  - claude_leads.safety_checkpoint: stash (options: stash, wip-commit, none)
  - claude_leads.review.max_iterations: 3 (レビュー修正ループの上限)

**Language setting:**
When `language` is set to a non-English value (e.g., `ja`), all Codex prompts will be prefixed with a language directive:
```
**{language}で回答してください。**

[Original prompt content]
```

This ensures Codex responds in the specified language regardless of the prompt template language.

### Step 1a: Determine Workflow

After loading settings, determine which workflow to use:

**If `workflow` is explicitly set to `codex-leads` or `claude-leads`:**
- Use that workflow directly.

**If `workflow` is `auto` (default):**

Always select `codex-leads`.

> **Note:** `auto` は常に `codex-leads` を選択する。`claude-leads` はClaude側のコンテキスト/ターン消費が大きく、Codex実装待ちの間にタイムアウトする問題があるため、明示的に `workflow: claude-leads` を指定した場合のみ有効。

Report the selected workflow to the user:
```
Workflow: codex-leads (auto-selected, default)
```

**Update session state with resolved settings:**

After settings and workflow are determined, update the session state file (Step 0a saved only mode/threadId with defaults):

```bash
export CODEX_SKILL_CONTEXT=1
# Re-save with resolved settings (TASK_ID and MODE/THREAD_ID from Step 0a)
codex_save_session_state "$TASK_ID" "$MODE" "$THREAD_ID" "${SANDBOX_SETTING:-read-only}" "${WORKFLOW:-codex-leads}"
```

**After workflow is determined:**
- If `codex-leads` → Continue to **Step 2** (existing workflow)
- If `claude-leads` → Jump to **Step 2c** (Claude-led workflow)

---

## Codex-Leads Workflow (従来のワークフロー)

> This is the default workflow where **Codex plans and reviews, Claude implements**.
> Active when `workflow` is `auto` (default) or explicitly set to `codex-leads`.

### Step 2: Analyze Task

**Before starting, create a task to track progress:**

Use TaskCreate:
- subject: "Analyze task and gather context"
- description: "Load settings, identify affected files, prepare context for Codex"
- activeForm: "Analyzing task"

Then use TaskUpdate to set status to `in_progress`.

**Perform analysis:**
1. Identify the core objective from the task description
2. List potentially affected files
3. Gather relevant context by reading key files
4. Prepare a summary for Codex

### Step 3: Request Plan from Codex

**Task transition:**
1. Mark "Analyze task and gather context" as `completed`
2. Use TaskCreate:
   - subject: "Get implementation plan from Codex"
   - description: "Request plan, wait for completion, process response"
   - activeForm: "Getting plan from Codex"
3. Use TaskUpdate to set status to `in_progress`

**Choose path based on communication mode (Step 0a):**

#### MCP Path (primary)

Call `mcp__codex__codex` to start a new stateful session:

```
mcp__codex__codex(
  prompt: "[Planning prompt - same content as Bash path's heredoc below]",
  developer-instructions: "[Language directive, e.g., '日本語で回答してください。...']",
  sandbox: "read-only",
  model: "[model setting if specified]",
  cwd: "[project directory]"
)
```

- The returned `threadId` is saved for subsequent steps (Step 5a, 7, 8)
- Update session state with the new threadId
- Response is read directly from the tool result (no file I/O, no ANSI stripping needed)
- If MCP call fails → fall through to Bash path below

#### Bash Path (fallback)

**1. Prepare prompt file:**
```bash
export CODEX_SKILL_CONTEXT=1

# Source helpers
HELPERS=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh" ]; then
  HELPERS="${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh"
elif [ -d ~/.claude/plugins/cache/codex-collab ]; then
  HELPERS=$(ls -td ~/.claude/plugins/cache/codex-collab/codex-collab/*/scripts/codex-helpers.sh 2>/dev/null | head -1)
fi
if [ -z "$HELPERS" ] || [ ! -f "$HELPERS" ]; then
  HELPERS="$(pwd)/scripts/codex-helpers.sh"
fi
[ -f "$HELPERS" ] && source "$HELPERS"

TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
mkdir -p "$TMP_DIR"
CODEX_OUTPUT="$TMP_DIR/codex-plan-output.md"
CODEX_PROMPT="$TMP_DIR/codex-plan-prompt.txt"
rm -f "$CODEX_OUTPUT"

LANGUAGE="${LANGUAGE:-en}"
LANG_DIRECTIVE=$(codex_get_language_directive "$LANGUAGE")

cat > "$CODEX_PROMPT" << EOF
${LANG_DIRECTIVE}You are collaborating with Claude Code. Your role is to create a detailed implementation plan.

**IMPORTANT**: If you reference any files, always re-read them from disk even if you have read them before in this session. Ignore any cached content from earlier in this conversation.

## Task
[Task description]

## Context
[Relevant code context]

## Required Output

### 1. Files to Modify
List each file with type of change (create/modify/delete)

### 2. Implementation Steps
Numbered steps in execution order

### 3. Risk Assessment
Potential issues and edge cases

### 4. Test Considerations
What should be tested

## Response Format

At the end of your response, include a metadata block:

\`\`\`
---
status: continue or stop
open_questions:  # if any clarification needed
  - question 1
decisions:  # key decisions made
  - decision 1
---
\`\`\`

Use \`status: continue\` if you have questions, \`status: stop\` if the plan is complete.

Provide your plan now.
EOF
```

**2. Run Codex exec:**

```bash
export CODEX_SKILL_CONTEXT=1

# Source helpers
HELPERS=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh" ]; then
  HELPERS="${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh"
elif [ -d ~/.claude/plugins/cache/codex-collab ]; then
  HELPERS=$(ls -td ~/.claude/plugins/cache/codex-collab/codex-collab/*/scripts/codex-helpers.sh 2>/dev/null | head -1)
fi
if [ -z "$HELPERS" ] || [ ! -f "$HELPERS" ]; then
  HELPERS="$(pwd)/scripts/codex-helpers.sh"
fi
[ -f "$HELPERS" ] && source "$HELPERS"

TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
CODEX_PROMPT="$TMP_DIR/codex-plan-prompt.txt"
CODEX_OUTPUT="$TMP_DIR/codex-plan-output.md"
SANDBOX="${SANDBOX_SETTING:-read-only}"
MODEL="${MODEL_SETTING:-}"

codex_run_exec "$CODEX_PROMPT" "$CODEX_OUTPUT" "$SANDBOX" "$MODEL"
echo "Codex plan saved to: $CODEX_OUTPUT"
```

> **Important:** Set the Bash tool's `timeout` parameter to `min(wait_timeout + 60, 600) * 1000` milliseconds. Example: for 180s wait, use `timeout: 240000`. Max: 600000ms (10 minutes).
> For long-running tasks, use `run_in_background: true` on the Bash tool.

**Options to include based on settings:**
- `-m, --model <model>` - Specify model (e.g., o4-mini, o3) from `model` setting
- `-s, --sandbox <mode>` - read-only | workspace-write | danger-full-access from `sandbox` setting

### Step 5: Read and Process Response

**Task transition:**
1. Mark "Get implementation plan from Codex" as `completed`
2. Use TaskCreate:
   - subject: "Review and approve plan"
   - description: "Validate plan completeness, present to user for approval"
   - activeForm: "Reviewing plan"
3. Use TaskUpdate to set status to `in_progress`

Once completion is detected:

1. Read the output file: `cat "$CODEX_OUTPUT"`
2. Parse the YAML response from Codex
3. Check `next_action` field (evaluated first, takes precedence):
   - If `next_action: continue` or `type: action_request` → Go to Step 5a (Discussion Loop)
   - If `next_action: stop` → Continue to Step 6
   - If `next_action` is missing → Default to `stop` for task_card/review, `continue` for action_request
4. Validate for completeness:
   - [ ] Files to modify are clearly listed
   - [ ] Steps are specific and actionable
   - [ ] Risks are identified

Present the plan to the user and wait for confirmation before implementing.

### Step 5a: Multi-turn Exchange Loop (Optional)

If Codex requests clarification or wants to continue the exchange:

**0. Check if exchange is enabled:**
- If `exchange.enabled: false` → Skip this step, proceed to Step 6

**1. Track exchange state:**
- Increment round counter
- Check if round < exchange.max_iterations (default: 3)

**Choose path based on communication mode:**

#### MCP Path (primary) — Simplified multi-turn

MCP mode eliminates the need for history reconstruction. The thread retains full conversation context.

```
mcp__codex__codex-reply(
  threadId: "[threadId from Step 3]",
  prompt: "[Your response to Codex's question/request]

Please respond with next_action: stop when the plan is complete."
)
```

- **No history management needed**: The thread preserves all prior context
- `exchange.history_mode: summarize` logic is unnecessary in MCP mode
- Simply send the new message; Codex sees the full conversation
- Parse response directly from tool result
- Return to Step 5

#### Bash Path (fallback) — History reconstruction

For each round, include conversation history in the prompt. Since `codex exec` is stateless, context must be explicitly provided:

- **Direct recent rounds (last 2):** Include full text of recent exchanges
- **Older rounds:** Summarize key decisions, unresolved questions, constraints

```
## Conversation History

### Previous Rounds Summary (if round > 2)
[Summarize key decisions, unresolved questions, constraints]

### Round {N-1}
Claude: [Your previous message]
Codex: [Codex's response]

### Round {N}
Claude: [Your current response to Codex's question/request]

## Continue Discussion

[Your response addressing Codex's question or providing requested information]

Please respond with next_action: stop when exchange is complete.
```

- Write updated prompt to file
- Run `codex exec` with the updated prompt
- Return to Step 5

#### Common for both paths

**4. User confirmation (based on exchange.user_confirm setting):**
- `never`: Fully automatic exchange
- `always`: Confirm each round
- `on_important` (default): Confirm only for major decisions

**5. Force stop conditions:**
- round >= exchange.max_iterations → Summarize and proceed
- Repeated same question → Ask user for direction

### Step 6: Implement

**Task transition:**
1. Mark "Review and approve plan" as `completed`
2. Use TaskCreate:
   - subject: "Implement changes"
   - description: "Execute plan step by step, track modifications"
   - activeForm: "Implementing changes"
3. Use TaskUpdate to set status to `in_progress`

Execute the plan step by step:
1. Make changes as specified
2. Track all modifications
3. Prepare diff summary for review

### Step 7: Request Review from Codex

**Task transition:**
1. Mark "Implement changes" as `completed`
2. Use TaskCreate:
   - subject: "Request review from Codex"
   - description: "Stage changes, request review, process feedback"
   - activeForm: "Getting review from Codex"
3. Use TaskUpdate to set status to `in_progress`

**0. Stage changes for Codex visibility (important!):**
```bash
git add -A
```
> **Why?** Staging ensures all changes are visible to Codex regardless of its file discovery method.
> This is staging only, not a commit. Run `git reset` after review to unstage if needed.

**Choose path based on communication mode:**

#### MCP Path (primary) — Review via thread continuation

MCP mode does not expose `codex review --uncommitted`, so embed the diff in the prompt.

**1. Get diff and determine tier:**
```bash
export CODEX_SKILL_CONTEXT=1

# Source helpers
HELPERS=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh" ]; then
  HELPERS="${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh"
elif [ -d ~/.claude/plugins/cache/codex-collab ]; then
  HELPERS=$(ls -td ~/.claude/plugins/cache/codex-collab/codex-collab/*/scripts/codex-helpers.sh 2>/dev/null | head -1)
fi
if [ -z "$HELPERS" ] || [ ! -f "$HELPERS" ]; then
  HELPERS="$(pwd)/scripts/codex-helpers.sh"
fi
[ -f "$HELPERS" ] && source "$HELPERS"

DIFF_CONTENT=$(git diff --cached)
DIFF_TIER=$(codex_diff_tier "$DIFF_CONTENT")
DIFF_STAT=$(git diff --cached --stat)

echo "Diff tier: $DIFF_TIER ($(echo "$DIFF_CONTENT" | wc -l) lines)"
echo "$DIFF_STAT"
```

**2. Build review prompt based on diff tier:**
- **small** (~500 lines以下): diff 全文を埋め込み
- **medium** (~500-2000 lines): `--stat` + 重要ファイルのみ hunk 全文
- **large** (2000 lines超): `--stat` + 変更サマリ。Bash fallback (`codex review --uncommitted`) を推奨

**3. Send review request via MCP:**

```
mcp__codex__codex-reply(
  threadId: "[threadId from Step 3]",
  prompt: "Review the following implementation changes.

## Diff Statistics
[git diff --cached --stat output]

## Changes
[diff content based on tier]

## Review Request
1. Does implementation match the plan?
2. Code quality and maintainability?
3. Bugs and issues? Mark with [P1] (critical), [P2] (high), [P3] (medium), [P4] (low).
4. Security vulnerabilities?
5. Verdict: PASS / CONDITIONAL / FAIL

Include a metadata block at the end:
---
verdict: pass / conditional / fail
findings:
  - severity: low / medium / high
    message: description
---"
)
```

- Codex has the plan context from the same thread (no need to resend plan)
- Verdict is parsed directly from the response (no `codex_infer_verdict()` needed)
- If MCP fails → fall through to Bash path

> **Note:** For large diffs, prefer Bash fallback with `codex review --uncommitted` which handles diff collection natively.

#### Bash Path (fallback)

**1. Run review using `codex review` (primary) with `codex exec` fallback:**

```bash
export CODEX_SKILL_CONTEXT=1

# Source helpers
HELPERS=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh" ]; then
  HELPERS="${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh"
elif [ -d ~/.claude/plugins/cache/codex-collab ]; then
  HELPERS=$(ls -td ~/.claude/plugins/cache/codex-collab/codex-collab/*/scripts/codex-helpers.sh 2>/dev/null | head -1)
fi
if [ -z "$HELPERS" ] || [ ! -f "$HELPERS" ]; then
  HELPERS="$(pwd)/scripts/codex-helpers.sh"
fi
[ -f "$HELPERS" ] && source "$HELPERS"

TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
mkdir -p "$TMP_DIR"
CODEX_REVIEW="$TMP_DIR/codex-review-output.md"
MODEL="${MODEL_SETTING:-}"
LANGUAGE="${LANGUAGE:-en}"
LANG_DIRECTIVE=$(codex_get_language_directive "$LANGUAGE")
rm -f "$CODEX_REVIEW"

# Primary: codex review --uncommitted
# Note: codex review --uncommitted does not accept a custom prompt.
# Custom review instructions are provided via the fallback codex exec path.
REVIEW_EXIT=0
codex_run_review "$CODEX_REVIEW" "$MODEL" || REVIEW_EXIT=$?

if [ "$REVIEW_EXIT" -ne 0 ]; then
  echo "codex review failed (exit=$REVIEW_EXIT), falling back to codex exec..."

  # Fallback: codex exec with diff file reference
  REVIEW_PROMPT="$TMP_DIR/codex-review-prompt.txt"
  DIFF_FILE="$TMP_DIR/codex-review-diff.txt"
  git diff --cached > "$DIFF_FILE"
  DIFF_FILE_ABS="$(cd "$(dirname "$DIFF_FILE")" && pwd)/$(basename "$DIFF_FILE")"

  cat > "$REVIEW_PROMPT" << EOF
${LANG_DIRECTIVE}Review the implementation described below.

## Original Plan
[Plan from Step 3]

## Changes Made

The diff is saved in the following file. Please read it:
\`\`\`
$DIFF_FILE_ABS
\`\`\`

If you cannot access the file, respond with:
\`\`\`
---
status: stop
verdict: conditional
message: Unable to access diff file
---
\`\`\`

## Review Request

### 1. Alignment Check
Does implementation match the plan?

### 2. Code Quality
Rate readability and maintainability

### 3. Bugs and Issues
List any problems found. Mark with [P1] (critical), [P2] (high), [P3] (medium), [P4] (low).

### 4. Security Check
Any vulnerabilities?

### 5. Verdict
- PASS: No critical issues
- CONDITIONAL: Acceptable with improvements
- FAIL: Critical issues found

## Response Format

At the end of your response, include a metadata block:

\`\`\`
---
status: stop
verdict: pass / conditional / fail
findings:  # if any issues found
  - severity: low / medium / high
    message: description of issue
---
\`\`\`

Provide your review now.
EOF

  SANDBOX="${SANDBOX_SETTING:-read-only}"
  codex_run_exec "$REVIEW_PROMPT" "$CODEX_REVIEW" "$SANDBOX" "$MODEL"
fi

echo "Codex review saved to: $CODEX_REVIEW"
```

### Step 8: Handle Review Result

**CRITICAL: Always iterate until PASS is received or max iterations reached.**

Claude must NOT give up after a single review response. The review loop should continue until:
- Verdict is `pass`
- Max iterations reached (default: 5)
- User explicitly requests to stop

**Choose path based on communication mode:**

#### MCP Path — Direct response parsing

In MCP mode, Claude reads the review response directly from the tool result:

- Parse verdict directly from the response text (look for `verdict: pass/conditional/fail` in metadata block, or `[P1]-[P4]` markers)
- No `codex_infer_verdict()` bash function needed — Claude can reason about the response directly
- For re-review after fixes:
  ```
  mcp__codex__codex-reply(
    threadId: "[same threadId]",
    prompt: "I've applied the following fixes based on your review:
  [description of fixes]

  Updated diff:
  [new git diff --cached output]

  Please re-review. Provide verdict: pass / conditional / fail."
  )
  ```
- Thread retains previous review context, so Codex can compare against prior findings

#### Bash Path — File-based parsing

**8.0 Parse verdict from response:**

Use `codex_infer_verdict()` for unified verdict parsing:

```bash
export CODEX_SKILL_CONTEXT=1

# Source helpers (same loading pattern as Step 7)
HELPERS=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh" ]; then
  HELPERS="${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh"
elif [ -d ~/.claude/plugins/cache/codex-collab ]; then
  HELPERS=$(ls -td ~/.claude/plugins/cache/codex-collab/codex-collab/*/scripts/codex-helpers.sh 2>/dev/null | head -1)
fi
if [ -z "$HELPERS" ] || [ ! -f "$HELPERS" ]; then
  HELPERS="$(pwd)/scripts/codex-helpers.sh"
fi
[ -f "$HELPERS" ] && source "$HELPERS"

TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
CODEX_REVIEW="$TMP_DIR/codex-review-output.md"

REVIEW_RESPONSE=$(cat "$CODEX_REVIEW")

# Unified verdict inference: metadata → [P1]-[P4] → no-findings pass
VERDICT=$(codex_infer_verdict "$REVIEW_RESPONSE") || true

# Extract findings for fix iteration
FINDINGS=$(codex_extract_review_findings "$REVIEW_RESPONSE")

echo "Detected verdict: $VERDICT"
if [ -n "$FINDINGS" ]; then
  echo "Findings:"
  echo "$FINDINGS"
fi
```

#### Common handling for both paths

**8.1 If verdict is missing or unclear:**

1. **Check for file access failure (fallback path only):**
   - If response contains "Unable to access diff file" → Retry with embedded diff

2. **Retry with embedded diff** (fallback for file access failure):
   ```bash
   DIFF_FILE="$TMP_DIR/codex-review-diff.txt"
   DIFF_CONTENT=$(cat "$DIFF_FILE")
   REVIEW_PROMPT="$TMP_DIR/codex-review-prompt.txt"
   cat > "$REVIEW_PROMPT" << EOF
   前回、差分ファイルにアクセスできなかったようです。
   差分を直接含めて再度レビューをお願いします。

   ## 差分

   \`\`\`diff
   ${DIFF_CONTENT}
   \`\`\`

   Mark findings with [P1] (critical), [P2] (high), [P3] (medium), [P4] (low).
   verdict: pass / conditional / fail で回答してください。
   EOF
   ```

3. **Retry with simplified prompt** (up to 3 retries)

4. **If still no verdict after retries:**
   - Treat as `conditional` and continue to 8.3

**8.2 If PASS:**

Report completion to user with summary. Task complete.

**8.3 If CONDITIONAL:**

1. If specific findings (from `codex_extract_review_findings()`) → Apply fixes and re-request review
2. If no specific issues → Re-review with clarification
3. Continue iteration until pass or max iterations

**8.4 If FAIL:**

1. Extract specific issues from findings
2. Apply fixes based on Codex's feedback
3. Stage changes: `git add -A`
4. Re-request review with updated diff
5. Return to Step 8

**8a. Review Iteration Loop (Full Implementation):**

```
review_round = 0
max_rounds = review.max_iterations (default: 5)
verdict_retries = 0
max_verdict_retries = 3

WHILE review_round < max_rounds:
  review_round++

  1. Stage changes: git add -A
  2. Run review (mode-dependent):
     MCP mode:
       a. Get diff, determine tier (codex_diff_tier)
       b. mcp__codex__codex-reply(threadId, review_prompt_with_diff)
       c. Parse verdict directly from response
     Bash mode:
       a. Try codex_run_review() (primary)
       b. If non-zero exit → fallback to codex_run_exec() with diff
       c. Parse verdict via codex_infer_verdict()
       d. Extract findings via codex_extract_review_findings()

  IF Bash fallback path AND response contains "Unable to access diff file":
    Rebuild prompt with diff content embedded
    review_round--
    CONTINUE

  IF verdict is empty (unable to determine):
    verdict_retries++
    IF verdict_retries < max_verdict_retries:
      Send follow-up asking for explicit verdict
      (MCP: codex-reply, Bash: new codex exec)
      CONTINUE
    ELSE:
      verdict = "conditional" (fallback)

  IF verdict == "pass":
    BREAK → Success

  IF verdict == "conditional":
    IF specific_findings_exist:
      Apply fixes
    ELSE:
      Re-request with clarification
    CONTINUE

  IF verdict == "fail":
    Apply fixes based on findings
    CONTINUE

IF review_round >= max_rounds AND verdict != "pass":
  Report: "Max review iterations reached. Final verdict: {verdict}"
  Ask user if they want to continue or accept current state
```

**User confirmation (based on review.user_confirm setting):**
- `never` (default): Auto-iterate without confirmation
- `always`: Confirm each round
- `on_important`: Confirm only for high-severity findings

### Step 9: Cleanup

**Task transition:**
1. Mark "Request review from Codex" as `completed`
2. Report completion to user

Remove temporary files:
```bash
TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
rm -f "$TMP_DIR/codex-plan-output.md" "$TMP_DIR/codex-plan-prompt.txt"
rm -f "$TMP_DIR/codex-review-output.md" "$TMP_DIR/codex-review-prompt.txt"
rm -f "$TMP_DIR/codex-review-diff.txt"
```

---

## Claude-Leads Workflow (新規ワークフロー)

> This workflow has **Claude plan and review, Codex implement**.
> Active only when `workflow` is explicitly set to `claude-leads`.
>
> **Key difference**: Codex runs with `workspace-write` sandbox to make file changes directly.

**Responsibility Boundary:**
| Role | Responsibility |
|------|---------------|
| **Claude** | Quality gate: deep analysis, planning, review, approval |
| **Codex** | Execution engine: accurate implementation per plan |
| **User** | Final approval: plan approval and ultimate decision authority |

> Claude bears responsibility for plan quality and review thoroughness. Codex bears responsibility for faithful execution. The user has final say at the plan approval step (Step 5c).

### Step 2c: Deep Codebase Analysis (Claude)

**Create a task to track progress:**

Use TaskCreate:
- subject: "Deep codebase analysis for planning"
- description: "Analyze codebase, identify affected files, understand architecture"
- activeForm: "Analyzing codebase"

Then use TaskUpdate to set status to `in_progress`.

**Perform deep analysis:**

Claude should thoroughly analyze the codebase using Read, Glob, and Grep:

1. **Understand the task**: Parse the core objective from the task description
2. **Map affected files**: Use Glob and Grep to find all relevant files
3. **Read key files**: Read each affected file to understand current implementation
4. **Understand dependencies**: Trace imports, function calls, and data flow
5. **Check existing tests**: Find related test files and understand test patterns
6. **Review recent changes**: Use `git log` to understand recent context

### Step 3c: Create Detailed Implementation Plan (Claude)

**Task transition:**
1. Mark "Deep codebase analysis for planning" as `completed`
2. Use TaskCreate:
   - subject: "Create implementation plan"
   - description: "Design detailed step-by-step plan based on analysis"
   - activeForm: "Creating plan"
3. Use TaskUpdate to set status to `in_progress`

Based on the analysis, create a detailed implementation plan that includes:

1. **Files to Modify**: List each file with type of change (create/modify/delete)
2. **Implementation Steps**: Numbered steps in execution order with specific code changes
3. **Risk Assessment**: Potential issues and edge cases
4. **Test Considerations**: What should be tested

### Step 4c: Plan Consultation with Codex (Optional)

> This step is optional and controlled by `claude_leads.consult_codex` setting (default: true).
> Skip this step if `consult_codex: false`.

**Purpose:** Get Codex's perspective on the plan before implementation.

**Choose path based on communication mode:**

#### MCP Path (primary)

Start a new MCP session for consultation (read-only sandbox):

```
mcp__codex__codex(
  prompt: "[Consultation prompt - same content as Bash path below]",
  developer-instructions: "[Language directive]",
  sandbox: "read-only",
  model: "[model setting if specified]",
  cwd: "[project directory]"
)
```

- This creates a separate thread (Thread B) from the codex-leads thread
- Save the threadId as named thread: `codex_save_thread "$TASK_ID" "threadB" "$THREAD_B_ID"`
- Parse response directly from tool result
- If MCP fails → fall through to Bash path

#### Bash Path (fallback)

**1. Prepare consultation prompt:**

```bash
export CODEX_SKILL_CONTEXT=1

# Source helpers
HELPERS=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh" ]; then
  HELPERS="${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh"
elif [ -d ~/.claude/plugins/cache/codex-collab ]; then
  HELPERS=$(ls -td ~/.claude/plugins/cache/codex-collab/codex-collab/*/scripts/codex-helpers.sh 2>/dev/null | head -1)
fi
if [ -z "$HELPERS" ] || [ ! -f "$HELPERS" ]; then
  HELPERS="$(pwd)/scripts/codex-helpers.sh"
fi
[ -f "$HELPERS" ] && source "$HELPERS"

TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
mkdir -p "$TMP_DIR"
CONSULT_PROMPT="$TMP_DIR/codex-consult-prompt.txt"
CONSULT_OUTPUT="$TMP_DIR/codex-consult-output.md"
rm -f "$CONSULT_OUTPUT"

LANGUAGE="${LANGUAGE:-en}"
LANG_DIRECTIVE=$(codex_get_language_directive "$LANGUAGE")

cat > "$CONSULT_PROMPT" << EOF
${LANG_DIRECTIVE}You are reviewing an implementation plan created by Claude Code before execution.

**IMPORTANT**: If you reference any files, always re-read them from disk.

## Task
[Task description]

## Proposed Plan
[Claude's implementation plan from Step 3c]

## Review Request

Please review this plan and provide feedback on:

### 1. Feasibility
Can this plan be executed as-is? Any missing steps?

### 2. Risks
Any risks or edge cases not covered?

### 3. Improvements
Suggestions for better approach or optimization?

### 4. Verdict
- APPROVE: Plan is solid, proceed with implementation
- SUGGEST: Plan is acceptable with suggested improvements
- RETHINK: Significant issues, plan needs revision

## Response Format

At the end of your response, include a metadata block:

\`\`\`
---
status: stop
verdict: approve / suggest / rethink
suggestions:
  - suggestion 1
---
\`\`\`

Provide your review now.
EOF
```

**2. Run Codex consultation:**

```bash
export CODEX_SKILL_CONTEXT=1

HELPERS=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh" ]; then
  HELPERS="${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh"
elif [ -d ~/.claude/plugins/cache/codex-collab ]; then
  HELPERS=$(ls -td ~/.claude/plugins/cache/codex-collab/codex-collab/*/scripts/codex-helpers.sh 2>/dev/null | head -1)
fi
if [ -z "$HELPERS" ] || [ ! -f "$HELPERS" ]; then
  HELPERS="$(pwd)/scripts/codex-helpers.sh"
fi
[ -f "$HELPERS" ] && source "$HELPERS"

TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
CONSULT_PROMPT="$TMP_DIR/codex-consult-prompt.txt"
CONSULT_OUTPUT="$TMP_DIR/codex-consult-output.md"
SANDBOX="${SANDBOX_SETTING:-read-only}"
MODEL="${MODEL_SETTING:-}"

codex_run_exec "$CONSULT_PROMPT" "$CONSULT_OUTPUT" "$SANDBOX" "$MODEL"
echo "Codex consultation saved to: $CONSULT_OUTPUT"
```

**3. Process Codex's feedback:**

- If `verdict: approve` → Proceed to Step 5c
- If `verdict: suggest` → Incorporate suggestions into the plan, proceed to Step 5c
- If `verdict: rethink` → Revise plan based on feedback, optionally re-consult

### Step 5c: User Approval

**Task transition:**
1. Mark "Create implementation plan" as `completed`
2. Use TaskCreate:
   - subject: "Get user approval for plan"
   - description: "Present plan (with Codex feedback if available) for user approval"
   - activeForm: "Waiting for user approval"
3. Use TaskUpdate to set status to `in_progress`

Present the plan to the user, including Codex's feedback if consultation was performed.

Use AskUserQuestion to get user approval:
- Show the plan summary
- If Codex suggested improvements, highlight them
- Ask user to approve, modify, or reject the plan

**If user approves** → Continue to Step 6c
**If user requests modifications** → Update plan and re-present
**If user rejects** → End workflow

### Step 6c: Safety Checkpoint

**Before Codex makes any changes, save the current state.**

Based on `claude_leads.safety_checkpoint` setting:

**`stash` (default):**
```bash
export CODEX_SKILL_CONTEXT=1
git stash push -m "codex-collab: pre-implementation checkpoint $(date +%Y%m%d-%H%M%S)"
echo "Safety checkpoint created (git stash)"
```

**`wip-commit`:**
```bash
export CODEX_SKILL_CONTEXT=1
git add -A
git commit -m "WIP: codex-collab pre-implementation checkpoint" --allow-empty
echo "Safety checkpoint created (WIP commit)"
```

**`none`:**
- Skip checkpoint (user accepts risk)

### Step 7c: Codex Implementation

**Task transition:**
1. Mark "Get user approval for plan" as `completed`
2. Use TaskCreate:
   - subject: "Codex implements changes"
   - description: "Send plan to Codex with workspace-write sandbox, monitor implementation"
   - activeForm: "Codex implementing"
3. Use TaskUpdate to set status to `in_progress`

**Choose path based on communication mode:**

#### MCP Path (primary)

Start a new MCP session for implementation (workspace-write sandbox — different from read-only consultation):

```
mcp__codex__codex(
  prompt: "[Implementation prompt - same content as Bash path below]",
  developer-instructions: "[Language directive]",
  sandbox: "workspace-write",
  model: "[model setting if specified]",
  cwd: "[project directory]"
)
```

- This creates Thread C (separate from consultation Thread B due to different sandbox)
- Save the threadId as named thread: `codex_save_thread "$TASK_ID" "threadC" "$THREAD_C_ID"`
- Response describes what was implemented
- If MCP fails → fall through to Bash path

#### Bash Path (fallback)

**1. Prepare implementation prompt:**

```bash
export CODEX_SKILL_CONTEXT=1

# Source helpers
HELPERS=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh" ]; then
  HELPERS="${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh"
elif [ -d ~/.claude/plugins/cache/codex-collab ]; then
  HELPERS=$(ls -td ~/.claude/plugins/cache/codex-collab/codex-collab/*/scripts/codex-helpers.sh 2>/dev/null | head -1)
fi
if [ -z "$HELPERS" ] || [ ! -f "$HELPERS" ]; then
  HELPERS="$(pwd)/scripts/codex-helpers.sh"
fi
[ -f "$HELPERS" ] && source "$HELPERS"

TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
mkdir -p "$TMP_DIR"
IMPL_PROMPT="$TMP_DIR/codex-impl-prompt.txt"
IMPL_OUTPUT="$TMP_DIR/codex-impl-output.md"
rm -f "$IMPL_OUTPUT"

LANGUAGE="${LANGUAGE:-en}"
LANG_DIRECTIVE=$(codex_get_language_directive "$LANGUAGE")

cat > "$IMPL_PROMPT" << EOF
${LANG_DIRECTIVE}You are implementing changes based on a plan created by Claude Code.

**IMPORTANT**: Execute the plan exactly as specified. If you encounter issues, describe them clearly.

## Task
[Task description]

## Implementation Plan
[Detailed plan from Step 3c, with any modifications from consultation/user feedback]

## Instructions

1. Implement each step in order
2. Create/modify/delete files as specified
3. Follow existing code style and patterns
4. Do NOT skip any steps

## Response Format

After implementation, include a metadata block:

\`\`\`
---
status: stop
files_changed:
  - path/to/file1.ts (modified)
  - path/to/file2.ts (created)
issues:
  - description of any issues encountered
---
\`\`\`

Begin implementation now.
EOF
```

**2. Run Codex implementation:**

```bash
export CODEX_SKILL_CONTEXT=1

HELPERS=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh" ]; then
  HELPERS="${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh"
elif [ -d ~/.claude/plugins/cache/codex-collab ]; then
  HELPERS=$(ls -td ~/.claude/plugins/cache/codex-collab/codex-collab/*/scripts/codex-helpers.sh 2>/dev/null | head -1)
fi
if [ -z "$HELPERS" ] || [ ! -f "$HELPERS" ]; then
  HELPERS="$(pwd)/scripts/codex-helpers.sh"
fi
[ -f "$HELPERS" ] && source "$HELPERS"

TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
IMPL_PROMPT="$TMP_DIR/codex-impl-prompt.txt"
IMPL_OUTPUT="$TMP_DIR/codex-impl-output.md"
SANDBOX="${CLAUDE_LEADS_SANDBOX:-workspace-write}"
MODEL="${MODEL_SETTING:-}"

codex_run_exec "$IMPL_PROMPT" "$IMPL_OUTPUT" "$SANDBOX" "$MODEL"
echo "Codex implementation saved to: $IMPL_OUTPUT"
```

> **Important:** The sandbox is set to `workspace-write` (configurable via `claude_leads.sandbox`). This allows Codex to create and modify files within the project directory.

### Step 8c: Claude Review

**Task transition:**
1. Mark "Codex implements changes" as `completed`
2. Use TaskCreate:
   - subject: "Review Codex's implementation"
   - description: "Review changes via git diff and file reading, verify correctness"
   - activeForm: "Reviewing implementation"
3. Use TaskUpdate to set status to `in_progress`

**Claude reviews the changes made by Codex:**

1. **Check git diff:**
```bash
export CODEX_SKILL_CONTEXT=1
git diff
git diff --stat
```

2. **CRITICAL: Plan-vs-diff validation (mandatory):**
   Compare `git diff --stat` output against the file list in the implementation plan (Step 3c).
   - If files **outside the plan** are modified → **immediately halt** and report to user
   - Ask user whether to: (a) accept the extra changes, (b) revert them, or (c) abort entirely

3. **Read modified files:** Use Read tool to examine each changed file
4. **Verify against plan:** Check that each step was implemented correctly
5. **Check for issues:**
   - Code quality and style consistency
   - Security vulnerabilities
   - Missing error handling
   - Test coverage gaps
6. **Run lint/test if available**

### Step 9c: Fix Iteration & Completion

**Review iteration loop (Claude-led):**

```
review_round = 0
max_rounds = claude_leads.review.max_iterations (default: 3)

WHILE review_round < max_rounds:
  review_round++

  1. Claude reviews changes (git diff + Read)
  2. IF issues found:
     a. Prepare fix instructions for Codex
     b. Send fix request (mode-dependent):
        MCP mode:
          threadC=$(codex_load_thread "$TASK_ID" "threadC")
          mcp__codex__codex-reply(threadId: threadC, prompt: "[fix instructions]")
          (Thread C continues — Codex has implementation context)
        Bash mode:
          Run codex exec with fix prompt (workspace-write sandbox)
     c. CONTINUE (re-review)
  3. IF no issues:
     BREAK → Success

IF review_round >= max_rounds AND issues remain:
  Report: "Max review iterations reached. Remaining issues:"
  List remaining issues
  Ask user for direction
```

**Fix prompt template:**

```bash
export CODEX_SKILL_CONTEXT=1

# Source helpers
HELPERS=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh" ]; then
  HELPERS="${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh"
elif [ -d ~/.claude/plugins/cache/codex-collab ]; then
  HELPERS=$(ls -td ~/.claude/plugins/cache/codex-collab/codex-collab/*/scripts/codex-helpers.sh 2>/dev/null | head -1)
fi
if [ -z "$HELPERS" ] || [ ! -f "$HELPERS" ]; then
  HELPERS="$(pwd)/scripts/codex-helpers.sh"
fi
[ -f "$HELPERS" ] && source "$HELPERS"

TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
FIX_PROMPT="$TMP_DIR/codex-fix-prompt.txt"

LANGUAGE="${LANGUAGE:-en}"
LANG_DIRECTIVE=$(codex_get_language_directive "$LANGUAGE")

cat > "$FIX_PROMPT" << EOF
${LANG_DIRECTIVE}Fix the following issues found during review.

## Issues to Fix
[List of specific issues with file paths and line numbers]

## Instructions
1. Fix each issue as described
2. Do not change anything else
3. Preserve existing code style

## Response Format
\`\`\`
---
status: stop
fixes_applied:
  - description of fix 1
  - description of fix 2
---
\`\`\`
EOF
```

**Completion:**

1. Mark "Review Codex's implementation" as `completed`
2. **Cleanup temporary files:**
```bash
export CODEX_SKILL_CONTEXT=1
TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
rm -f "$TMP_DIR/codex-consult-prompt.txt" "$TMP_DIR/codex-consult-output.md"
rm -f "$TMP_DIR/codex-impl-prompt.txt" "$TMP_DIR/codex-impl-output.md"
rm -f "$TMP_DIR/codex-fix-prompt.txt"
```
3. Report completion to user with summary of changes

---

## Error Handling

If `codex` command is not available:
- Inform user: "Codex CLI is not installed or not in PATH. Would you like to proceed with Claude-only mode?"
- If yes, continue without Codex planning/review

If Codex returns an error:
- Report the error from the output file
- Offer to retry or proceed manually

If timeout (`codex.wait_timeout`, default 180s) without completion:
1. **Check Codex status** - Is Codex still running?
2. **If still running** → Re-run with extended timeout (up to max 600000ms)
3. **If completed but no output** → Read partial output and report to user
4. **If Codex failed** → Report error and offer to retry or proceed manually

## Notes

- **Architecture**: MCP primary + Bash fallback のデュアルモード。
  - **MCP mode** (`mcp__codex__codex`/`codex-reply`): ステートフルな会話（threadId で文脈保持）。ANSI 除去不要、ファイル I/O 不要、直接レスポンス読み取り。
  - **Bash mode** (`codex exec`/`codex review`): ステートレス実行（従来動作）。MCP 未設定時の自動フォールバック。
- **Thread topology** (MCP mode):
  - codex-leads: Thread A（計画 → exchange → レビュー、全ステップで共有）
  - claude-leads: Thread B（壁打ち、read-only）、Thread C（実装 → 修正、workspace-write）
- **Communication mode detection**: Step 0a で `mcp__codex__codex` の軽量 probe を実行。成功 → MCP、失敗 → Bash。
- **Session state**: `tmp/codex-session-{task_id}.json` にモード、threadId、threads（名前付きスレッド）、sandbox 等を保存。Step 0a で mode/threadId を初期保存、Step 1a で settings 反映後に更新。claude-leads では `codex_save_thread()` で Thread B/C を個別に保存。compaction 復旧時に読み込み。
- **Diff tiering** (MCP review): small（~500行）→全文、medium（~2000行）→stat+重要ファイル、large（2000行超）→stat+サマリ（Bash推奨）。
- **Workflow modes**:
  - **codex-leads**: Traditional workflow. Codex plans/reviews, Claude implements. Uses `read-only` sandbox by default.
  - **claude-leads**: New workflow. Claude plans/reviews, Codex implements. Uses `workspace-write` sandbox by default.
  - **auto**: 常に `codex-leads` を選択。`claude-leads` は明示的に `workflow: claude-leads` を指定した場合のみ有効。
- **Stateless context** (Bash mode only): Since `codex exec` is stateless, all necessary context must be included in each prompt. For multi-turn exchanges, include conversation history (recent 2 rounds full text + older rounds summarized). MCP mode ではスレッドが文脈を保持するため不要。
- Output files are saved in project's `tmp/` directory. This directory is excluded by `.gitignore`.
- **Important**: Stage changes with `git add -A` before review so Codex can see new files
- **Multi-turn exchange** (codex-leads only): Use `next_action: continue|stop` to control exchange flow.
- **Review iteration** (codex-leads): Continue iterating until `pass` or max iterations (default: 5).
- **Claude-led review** (claude-leads): Claude reviews via `git diff` + Read. Max iterations controlled by `claude_leads.review.max_iterations` (default: 3).
- **Safety checkpoint** (claude-leads): Before Codex implementation, save state via git stash (default).
- **Timeout configuration**: `codex.wait_timeout` (default: 180s, max: 600s) controls how long to wait for Codex. Set Bash tool's `timeout` parameter to `min(wait_timeout + 60, 600) * 1000` milliseconds. MCP mode ではタイムアウトは MCP フレームワークが管理。
- **Background execution**: For long-running `codex exec` calls, use `run_in_background: true` on the Bash tool.

## Compact Recovery

If you've been compacted during this workflow:

1. Run `TaskList` to see current progress
2. Find the task with status `in_progress`
3. **Check session state** for communication mode recovery:

```bash
export CODEX_SKILL_CONTEXT=1

# Source helpers
HELPERS=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh" ]; then
  HELPERS="${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh"
elif [ -d ~/.claude/plugins/cache/codex-collab ]; then
  HELPERS=$(ls -td ~/.claude/plugins/cache/codex-collab/codex-collab/*/scripts/codex-helpers.sh 2>/dev/null | head -1)
fi
if [ -z "$HELPERS" ] || [ ! -f "$HELPERS" ]; then
  HELPERS="$(pwd)/scripts/codex-helpers.sh"
fi
[ -f "$HELPERS" ] && source "$HELPERS"

# Find the most recent session state
ls -t tmp/codex-session-*.json 2>/dev/null | head -3
```

4. **MCP mode recovery:** If session state shows `mode: mcp` with a valid `threadId`:
   - Use `mcp__codex__codex-reply(threadId, "Resuming after context compaction...")` to continue
   - For claude-leads: check `threads.threadB` / `threads.threadC` for the appropriate thread
   - Use `codex_load_thread "$TASK_ID" "threadB"` or `codex_load_thread "$TASK_ID" "threadC"`
   - If threadId is invalid (thread_not_found) → fall back to Bash mode
5. **Bash mode recovery:** Resume from the current step using existing patterns
6. Resume from the current step

**Task to Step mapping (codex-leads):**
| Task | Resume at |
|------|-----------|
| "Analyze task and gather context" | Step 2 |
| "Get implementation plan from Codex" | Step 3 |
| "Review and approve plan" | Step 5 |
| "Implement changes" | Step 6 |
| "Request review from Codex" | Step 7 |

**Task to Step mapping (claude-leads):**
| Task | Resume at |
|------|-----------|
| "Deep codebase analysis for planning" | Step 2c |
| "Create implementation plan" | Step 3c |
| "Get user approval for plan" | Step 5c |
| "Codex implements changes" | Step 7c |
| "Review Codex's implementation" | Step 8c |

**Recovery example (MCP mode):**
```
TaskList shows:
- [completed] Analyze task and gather context
- [in_progress] Get implementation plan from Codex

→ Read tmp/codex-session-*.json for threadId
→ If threadId exists → mcp__codex__codex-reply(threadId, resume_prompt)
→ If no threadId → fall back to Bash mode, re-run Codex request
```

**Recovery example (Bash mode):**
```
TaskList shows:
- [completed] Analyze task and gather context
- [in_progress] Get implementation plan from Codex

→ Resume at Step 3: check tmp/codex-plan-output.md for Codex response
→ If output exists → proceed to Step 5
→ If no output → re-run Codex request
```
