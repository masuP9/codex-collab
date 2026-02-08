---
name: Codex Collaboration
description: This skill should be used when the user asks to "collaborate with Codex", "use Codex for planning", "get Codex review", "delegate to Codex", "Codexと協調", "Codexにレビュー", "Codexに計画を作成させたい", "Codexに任せる", "Codexに委任", "Codexと連携", "Codexに相談", "Codexの意見", "Claude plans", "Claude-led", "Claudeが計画", "Claude主導", "Codexに実装させる", "Codexに実装を任せる", "Claudeがレビュー", or mentions coordinating tasks between Claude Code and Codex CLI.
---

# Codex Collaboration Skill

Coordinate tasks between Claude Code and OpenAI Codex CLI using adaptive workflow selection based on model strengths.

## Overview

This skill enables effective collaboration between two AI systems with **two workflow modes**:

**Codex-Leads (従来):**
- **Codex**: Planning, code review, architectural decisions
- **Claude Code**: Implementation, file operations, testing

**Claude-Leads (新規):**
- **Claude Code**: Deep analysis, planning, code review
- **Codex**: Fast implementation with workspace-write sandbox

デフォルト（`auto`）は常に **Codex-Leads** を選択。`claude-leads` は `workflow: claude-leads` を明示指定した場合のみ有効。

**通信方式**: すべての Codex 呼び出しは `codex exec`（ステートレス実行）を使用。プロンプトを stdin から受け取り、結果を stdout に出力してブロッキング終了します。`codex_run_exec()` が入出力、ANSI 除去、exit code ハンドリングを統合処理します。

## Prerequisites

Before starting collaboration:
1. Verify `codex` CLI is available: `which codex` or `codex --version`
2. Verify `codex exec` works: `echo "test" | codex exec -s read-only -`
3. Check for project settings in `.claude/codex-collab.local.md`
4. If Codex CLI unavailable, inform user and proceed with Claude-only mode

## Workflow: Review Type (Default)

### Phase 1: Task Analysis

When receiving a task for collaboration:

1. Parse the task description to identify:
   - Core objective
   - Affected files/components
   - Complexity level
   - Required context

2. Gather relevant context:
   - Read related files
   - Check existing tests
   - Review recent changes

### Phase 2: Request Plan from Codex

1. Prepare prompt and run codex exec:
```bash
source scripts/codex-helpers.sh
PROMPT_FILE=$(codex_write_prompt "$PLANNING_PROMPT" "plan")
OUTPUT_FILE="$(codex_tmp_path 'codex-plan-output.md')"
codex_run_exec "$PROMPT_FILE" "$OUTPUT_FILE" "read-only"
```

2. Read results from output file

### Phase 3: Implement Based on Plan

After receiving Codex's plan:

1. Validate the plan is reasonable
2. Present plan to user for confirmation
3. Execute implementation step by step
4. Track changes made

### Phase 4: Request Review from Codex

After implementation:

1. **Stage changes for Codex visibility** (important!):
```bash
git add -A
git reset -- tmp/ 2>/dev/null || true
```
> **Why?** Staging ensures all changes are visible to Codex regardless of its file discovery method.

2. Prepare review prompt and run codex exec:
```bash
source scripts/codex-helpers.sh
REVIEW_PROMPT_FILE=$(codex_write_prompt "$REVIEW_PROMPT" "review")
REVIEW_OUTPUT="$(codex_tmp_path 'codex-review-output.md')"
codex_run_exec "$REVIEW_PROMPT_FILE" "$REVIEW_OUTPUT" "read-only"
```

3. Read and process review results

The review prompt must request:
- Design alignment check
- Bug/vulnerability detection
- Improvement suggestions
- Verdict: Pass / Fail / Conditional

### Phase 5: Handle Review Result

Based on review verdict:

**Pass**: Report completion to user

**Conditional**:
1. Apply suggested improvements
2. Re-request review if significant changes

**Fail**:
1. Analyze failure reasons
2. Either fix issues or escalate to user

## Settings and Configuration

### Reading Project Settings

Check for `.claude/codex-collab.local.md` in project root:

```markdown
---
model: o4-mini
sandbox: read-only
---

# Project-specific instructions
```

Parse YAML frontmatter for:
- `model`: Codex model to use
- `sandbox`: read-only | workspace-write | danger-full-access
- `workflow`: Workflow mode (auto | codex-leads | claude-leads, default: auto; auto は常に codex-leads を選択)
- `exchange.enabled`: Enable planning exchange (default: true, codex-leads only)
- `exchange.max_iterations`: Maximum rounds for multi-turn exchange (default: 3)
- `exchange.user_confirm`: When to ask user confirmation (never | always | on_important)
- `exchange.history_mode`: How to handle history (full | summarize)
- `review.enabled`: Enable review iteration (default: true, codex-leads only)
- `review.max_iterations`: Maximum rounds for review iteration (default: 5)
- `review.user_confirm`: When to ask user confirmation for reviews (default: never)
- `claude_leads.sandbox`: Sandbox for Codex implementation (default: workspace-write)
- `claude_leads.consult_codex`: Enable plan consultation phase (default: true)
- `claude_leads.safety_checkpoint`: Pre-implementation checkpoint (stash | wip-commit | none, default: stash)
- `claude_leads.review.max_iterations`: Max review-fix iterations (default: 3)

### Settings Priority

Apply settings in this order (later overrides earlier):

1. **Safe defaults**: sandbox=read-only
2. **Global settings**: ~/.claude/codex-collab.local.md
3. **Project settings**: .claude/codex-collab.local.md
4. **Command arguments**: Explicit user request

### Safe Defaults

Always start with secure defaults:
- `workflow: auto` - 常に codex-leads を選択（claude-leads は明示指定時のみ）
- `sandbox: read-only` - Codex cannot modify files (codex-leads)
- `exchange.enabled: true` - Planning exchange enabled by default
- `exchange.max_iterations: 3` - Prevent runaway exchanges
- `exchange.user_confirm: on_important` - Ask user for major decisions
- `exchange.history_mode: summarize` - Efficient token usage
- `review.enabled: true` - Review iteration enabled by default
- `review.max_iterations: 5` - More iterations allowed (goal is clear, diff is small)
- `review.user_confirm: never` - Auto-iterate without confirmation
- `claude_leads.sandbox: workspace-write` - Codex can modify project files (claude-leads)
- `claude_leads.consult_codex: true` - Plan consultation enabled
- `claude_leads.safety_checkpoint: stash` - Git stash before implementation
- `claude_leads.review.max_iterations: 3` - Claude review iterations

## Quality Gates

### Plan Quality Criteria

A valid plan from Codex must include:
- [ ] Clear list of files to modify
- [ ] Specific changes for each file
- [ ] Rationale for approach
- [ ] Identified risks or concerns
- [ ] Test coverage considerations

If plan is incomplete, request clarification from Codex.

### Review Acceptance Criteria

Accept review as "Pass" only when:
- [ ] All changed files reviewed
- [ ] No critical bugs identified
- [ ] Security concerns addressed
- [ ] Design aligns with original plan
- [ ] Test coverage adequate

## Running Codex

### codex exec パターン

すべての Codex 呼び出しは `codex exec`（ステートレス実行）を使用します:

```bash
# ヘルパー関数を使用（推奨）
source scripts/codex-helpers.sh
PROMPT_FILE=$(codex_write_prompt "$PROMPT_CONTENT" "plan")
OUTPUT_FILE="$(codex_tmp_path 'codex-output.md')"
codex_run_exec "$PROMPT_FILE" "$OUTPUT_FILE" "read-only" "o4-mini"

# 直接実行
cat prompt.txt | codex exec -s read-only -m o4-mini - 2>&1 | tee output.md
```

### Codex CLI Options

- `-m, --model <model>` - Specify model (e.g., o4-mini, o3)
- `-s, --sandbox <mode>` - read-only | workspace-write | danger-full-access
- `-C, --cd <dir>` - Working directory
- `--full-auto` - Automatic execution mode
- `-` - Read prompt from stdin

### Important Notes

- Each `codex exec` call is stateless (no conversation history between calls)
- Include all necessary context in each prompt
- Use `-s read-only` for planning/review tasks (Codex won't modify files)
- Use `-s workspace-write` for implementation tasks (claude-leads workflow)
- Output may contain ANSI escape codes; use `codex_strip_ansi()` or `codex_run_exec()` to clean
- **Stdin input**: Use `cat file | codex exec -` format to avoid escaping issues
- **Timeout**: Bash tool has max 600s (10 minutes) timeout

## Error Handling

### CLI Unavailable

If `codex` command is not found:
1. Inform user: "Codex CLI is not installed or not in PATH"
2. Offer to proceed with Claude-only mode
3. Continue with standard Claude Code workflow

### Codex Timeout or Error

If `codex exec` returns non-zero exit code or times out:
1. Check error message in output file
2. Retry once with simplified prompt
3. If still failing, proceed manually and inform user

### Bash Tool Timeout

Bash tool has max 600s (10 minutes) timeout. For long-running tasks:
1. Set appropriate `codex.wait_timeout` setting
2. Consider breaking tasks into smaller parts
3. Use `run_in_background: true` for background execution

## Structured Communication Protocol

This plugin uses a minimal protocol header to enable structured communication between Claude Code and Codex CLI.

### Protocol Header

Every prompt to Codex includes a ~15-line protocol header:

```yaml
## Protocol (codex-collab/v1)
format: yaml
rules:
  - respond with exactly one top-level YAML mapping
  - include required fields: type, id, status, body
  - if unsure or blocked, use type=action_request with clarifying questions
types:
  task_card: {body: title, context, requirements, acceptance_criteria, proposed_steps, risks, test_considerations}
  result_report: {body: summary, changes, tests, risks, checks}
  action_request: {body: question, options, expected_response}
  review: {body: verdict, summary, findings, suggestions}
status: [ok, partial, blocked]
verdict: [pass, conditional, fail]
severity: [low, medium, high]
next_action: [continue, stop]
```

### Message Types

| Type | Purpose | Used By |
|------|---------|---------|
| `task_card` | Task definition with acceptance criteria | Codex (planning) |
| `result_report` | Execution results with check status | Claude (reporting) |
| `action_request` | Request for information or decision | Both |
| `review` | Review verdict and findings | Codex (review) |

### Parsing Strategy

- **Lenient**: Require only top-level envelope and core keys
- **Tolerant**: Accept extra fields and minor formatting differences
- **Fallback**: If YAML parsing fails, fall back to unstructured parsing

### Multi-turn Exchange

The protocol supports two independent iteration modes:

#### Planning Exchange (`exchange.*`)

Iterative discussion during planning phase:

**Flow Control:**
- `next_action: continue` - Request further exchange
- `next_action: stop` - Exchange complete
- `type: action_request` - Implies `next_action: continue`

**Settings:**
- `exchange.enabled: true` - Global kill-switch
- `exchange.max_iterations: 3` - Max rounds
- `exchange.user_confirm: on_important` - User confirmation timing
- `exchange.history_mode: summarize` - History management

**Termination Conditions:**
1. `next_action: stop` received
2. `exchange.max_iterations` reached
3. Repeated same question detected

#### Review Iteration (`review.*`)

Auto-iterate on review findings:

**Flow:**
1. Codex reviews → CONDITIONAL/FAIL
2. Claude fixes issues
3. Re-request review
4. Repeat until PASS or max reached

**Settings:**
- `review.enabled: true` - Enable auto-iteration
- `review.max_iterations: 5` - Higher than exchange (goal is clear, diff is small)
- `review.user_confirm: never` - Auto-iterate without confirmation

**Note:** `exchange.*` and `review.*` are completely independent (no inheritance).

## References

Detailed documentation in `references/`:

- **`protocol-cheatsheet.yaml`** - Minimal protocol header for prompts
- **`protocol-schema.yaml`** - Full protocol schema with examples
- **`planning-prompt.md`** - Template for requesting plans
- **`review-prompt.md`** - Template for requesting reviews
- **`codex-options.md`** - Codex CLI configuration options
- **`workflow-patterns.md`** - Alternative workflow patterns
