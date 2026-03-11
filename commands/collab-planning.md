---
name: collab-planning
description: Create and refine implementation plans collaboratively with Codex (plan only, no implementation)
argument-hint: [idea/task] [--mode codex|claude-only] [--max-iterations N]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, AskUserQuestion, mcp__codex__codex, mcp__codex__codex-reply
---

# Collaborative Planning

Create and refine an implementation plan through collaboration between Claude and Codex. **This skill produces a plan document only — it NEVER starts implementation.**

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
fi
```

### Step 1: Parse Arguments and Initialize

**1. Parse mode and options from arguments:**

Extract `--mode` and `--max-iterations` options from $ARGUMENTS if present:

```bash
export CODEX_SKILL_CONTEXT=1

# Parse arguments
ARGS="$ARGUMENTS"
MODE_OVERRIDE=""
MAX_ITERATIONS_OVERRIDE=""
TASK_DESCRIPTION=""

# Check for --mode flag
if echo "$ARGS" | grep -qE '\-\-mode\s+(codex|claude-only)'; then
  MODE_OVERRIDE=$(echo "$ARGS" | grep -oE '\-\-mode\s+(codex|claude-only)' | awk '{print $2}')
  ARGS=$(echo "$ARGS" | sed -E 's/--mode\s+(codex|claude-only)//')
fi

# Check for --max-iterations flag
if echo "$ARGS" | grep -qE '\-\-max-iterations\s+[0-9]+'; then
  MAX_ITERATIONS_OVERRIDE=$(echo "$ARGS" | grep -oE '\-\-max-iterations\s+[0-9]+' | awk '{print $2}')
  ARGS=$(echo "$ARGS" | sed -E 's/--max-iterations\s+[0-9]+//')
fi

# Remaining is the task description
TASK_DESCRIPTION=$(echo "$ARGS" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

echo "Mode override: ${MODE_OVERRIDE:-none}"
echo "Max iterations override: ${MAX_ITERATIONS_OVERRIDE:-none}"
echo "Task: $TASK_DESCRIPTION"
```

**2. Load settings and determine mode:**

```bash
export CODEX_SKILL_CONTEXT=1

# Read settings from config file
SETTINGS_FILE=".claude/codex-collab.local.md"
if [ -f "$SETTINGS_FILE" ]; then
  LANGUAGE=$(awk '/^language:/ {print $2}' "$SETTINGS_FILE" 2>/dev/null || echo "en")
  CONFIGURED_MAX_ITERATIONS=$(awk '/max_iterations:/ {print $2}' "$SETTINGS_FILE" 2>/dev/null || echo "3")
else
  LANGUAGE="en"
  CONFIGURED_MAX_ITERATIONS="3"
fi

# Determine mode
DEFAULT_MODE="claude-only"
if command -v codex &>/dev/null; then
  DEFAULT_MODE="codex"
fi

if [ -n "$MODE_OVERRIDE" ]; then
  MODE="$MODE_OVERRIDE"
  echo "Mode: $MODE (user specified)"
else
  MODE="$DEFAULT_MODE"
  if [ "$MODE" = "codex" ]; then
    echo "Mode: codex (auto-detected: Codex CLI available)"
  else
    echo "Mode: claude-only (auto-detected: Codex CLI not available)"
  fi
fi

# Set max iterations (override > config > default 3)
MAX_ITERATIONS="${MAX_ITERATIONS_OVERRIDE:-${CONFIGURED_MAX_ITERATIONS:-3}}"
echo "Max iterations: $MAX_ITERATIONS"
echo "Language: $LANGUAGE"
```

### Step 1b: Determine Communication Mode (MCP vs Bash)

**If mode = codex**, probe MCP availability:

Call `mcp__codex__codex` with a lightweight ping:
```
mcp__codex__codex(prompt: "ping", sandbox: "read-only")
```

- **Success** → MCP mode. Save the returned `threadId`.
- **Failure** (tool not available, permission denied, error) → Bash mode.

**Save session state:**

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

TASK_ID="planning-$$-$(date +%s)"
# MODE and THREAD_ID are set by the probe result above
# MODE="mcp" or "bash", THREAD_ID from probe response (empty for bash)
codex_save_session_state "$TASK_ID" "$MODE" "$THREAD_ID"
echo "Communication mode: $MODE (task_id: $TASK_ID)"
```

**3. Generate task ID and initialize state file:**

```bash
export CODEX_SKILL_CONTEXT=1

TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}/collab-planning"
mkdir -p "$TMP_DIR"

TASK_ID="${TASK_ID:-planning-$(date +%Y%m%d-%H%M%S)-$RANDOM}"
STATE_FILE="$TMP_DIR/${TASK_ID}.md"

# Create state file with placeholders
cat > "$STATE_FILE" << 'EOFSTATE'
---
schema: collab-planning/v1
task_id: __TASK_ID__
created: __TIMESTAMP__
task: "__TASK__"
mode: __MODE__
comm_mode: __COMM_MODE__
iteration: 0
max_iterations: __MAX_ITERATIONS__
status: in_progress
quality: pending
---

# Collaborative Plan: __TASK__

## Overview

**Task:** __TASK__
**Mode:** __MODE__
**Max Iterations:** __MAX_ITERATIONS__

## Iteration Log

EOFSTATE

# Safe replacement using awk
awk -v task_id="$TASK_ID" \
    -v timestamp="$(date -Iseconds)" \
    -v mode="${MODE:-codex}" \
    -v comm_mode="${COMM_MODE:-bash}" \
    -v max_iterations="${MAX_ITERATIONS:-3}" \
    -v task="$TASK_DESCRIPTION" \
    '{
      gsub(/__TASK_ID__/, task_id);
      gsub(/__TIMESTAMP__/, timestamp);
      gsub(/__MODE__/, mode);
      gsub(/__COMM_MODE__/, comm_mode);
      gsub(/__MAX_ITERATIONS__/, max_iterations);
      gsub(/__TASK__/, task);
      print
    }' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"

echo "State file: $STATE_FILE"
echo "Task ID: $TASK_ID"
```

### Step 2: Gather Context

**Collect information using Claude's tools:**

1. Use Glob to identify relevant files in the codebase
2. Use Grep to find related code patterns, interfaces, and dependencies
3. Use Read to examine key files in detail
4. Understand the current architecture and constraints
5. Identify all files that may need changes

**Build a context summary** (do NOT store this in the state file yet — it feeds into the draft):

```markdown
## Context Summary

### Relevant Files
- file1.ts: Description and role
- file2.ts: Description and role

### Current Architecture
[How things work today relevant to the task]

### Constraints and Dependencies
[Technical constraints, external dependencies, compatibility requirements]

### Related Patterns
[Existing patterns in the codebase that the plan should follow]
```

### Step 3: Draft Plan

Using the context gathered in Step 2 and the user's task description, create a plan following the **fixed template** from `skills/collab-planning/references/plan-draft-guide.md`:

```markdown
## Plan: [Title]

### 1. Purpose
[What this change achieves]

### 2. Scope Exclusions
[What is intentionally out of scope]

### 3. Work Breakdown (WBS)
| # | File | Action | Description |
|---|------|--------|-------------|
| 1 | path/to/file | create/modify/delete | Details |

### 4. Implementation Steps (reference only — NOT executed by this skill)
1. [Ordered concrete steps]

### 5. Risk Assessment
| Risk | Severity | Mitigation |
|------|----------|------------|
| ... | High/Medium/Low | ... |

### 6. Verification Methods
- [ ] [Test items]

### 7. Completion Criteria
- [ ] [Acceptance criteria]
```

**Important:** Store the current draft in a variable/file for submission to Codex. Also append the draft to the state file using Edit tool.

### Step 4: Submit Plan for Codex Review

**If mode = codex:**

**Choose communication path:**

#### MCP Path (primary)

**Iteration 1:** Start a new review session (or continue from Step 1b ping thread):

If a `threadId` already exists from the MCP probe, use `codex-reply`:
```
mcp__codex__codex-reply(
  threadId: "[threadId from probe]",
  prompt: "[Review prompt with plan draft — see template below]"
)
```

Otherwise start a new session:
```
mcp__codex__codex(
  prompt: "[Review prompt with plan draft]",
  developer-instructions: "[Language directive]",
  sandbox: "read-only",
  cwd: "[project directory]"
)
```
Save the returned `threadId`.

**Iteration 2+:** Continue the existing thread:
```
mcp__codex__codex-reply(
  threadId: "[threadId]",
  prompt: "[Updated plan + previous snapshot history]"
)
```
- **Key advantage**: Thread retains all prior context. Only send the updated plan and latest changes.
- Parse review feedback directly from tool result.
- If MCP fails → fall through to Bash path.

#### Bash Path (fallback)

1. Prepare review prompt:

```bash
export CODEX_SKILL_CONTEXT=1

# Source helpers
HELPERS=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh" ]; then
  HELPERS="${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh"
elif [ -d ~/.claude/plugins/cache/codex-collab ]; then
  HELPERS=$(ls -td ~/.claude/plugins/cache/codex-collab/codex-collab/*/scripts/codex-helpers.sh 2>/dev/null | head -1)
fi
[ -z "$HELPERS" ] || [ ! -f "$HELPERS" ] && HELPERS="$(pwd)/scripts/codex-helpers.sh"
[ -f "$HELPERS" ] && source "$HELPERS"

TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
PLANNING_DIR="$TMP_DIR/collab-planning"
mkdir -p "$TMP_DIR"

# Find state file
if [ -z "${TASK_ID:-}" ]; then
  STATE_FILE=$(ls -t "$PLANNING_DIR"/*.md 2>/dev/null | head -1)
  TASK_ID=$(basename "$STATE_FILE" .md)
else
  STATE_FILE="$PLANNING_DIR/${TASK_ID}.md"
fi

echo "Using state file: $STATE_FILE"

# Read current iteration and task from state file
CURRENT_ITERATION=$(grep '^iteration:' "$STATE_FILE" | awk '{print $2}')
MAX_ITERATIONS=$(grep '^max_iterations:' "$STATE_FILE" | awk '{print $2}')
TASK_DESC=$(awk -F': "' '/^task:/ {gsub(/"$/, "", $2); print $2}' "$STATE_FILE")

CURRENT_ITERATION=$((CURRENT_ITERATION + 1))

# Get language directive
SETTINGS_FILE=".claude/codex-collab.local.md"
if [ -f "$SETTINGS_FILE" ]; then
  LANGUAGE=$(awk '/^language:/ {print $2}' "$SETTINGS_FILE" 2>/dev/null || echo "en")
else
  LANGUAGE="en"
fi
LANG_DIRECTIVE=$(codex_get_language_directive "$LANGUAGE")

# Read current plan draft from state file (between "## Current Draft" and next ##)
PLAN_DRAFT=$(awk '/^## Current Draft$/,/^## [^C]/' "$STATE_FILE" | grep -v '^## ' || echo "(No draft yet)")

# Read snapshot history
SNAPSHOT_HISTORY=$(awk '/^## Snapshot History$/,/^## [^S]/' "$STATE_FILE" | grep -v '^## ' || echo "(No previous iterations)")

REVIEW_PROMPT="$TMP_DIR/collab-planning-review-prompt.txt"

cat > "$REVIEW_PROMPT" << EOF
${LANG_DIRECTIVE}You are a plan reviewer. Your job is to evaluate an implementation plan and provide structured feedback.

## Context

A plan has been drafted for the following task:

${TASK_DESC}

## Plan to Review

${PLAN_DRAFT}

## Previous Feedback History

${SNAPSHOT_HISTORY}

## Review Instructions

Evaluate the plan against these criteria:

1. **Completeness**: Does the WBS cover all necessary changes? Are there missing files or steps?
2. **Correctness**: Are the proposed changes technically sound? Any logical errors?
3. **Risk coverage**: Are significant risks identified? Are mitigations adequate?
4. **Actionability**: Are implementation steps clear enough to follow without ambiguity?
5. **Scope**: Is the scope appropriate? Too broad or too narrow?
6. **Verification**: Are test/verification methods sufficient to catch regressions?

Iteration ${CURRENT_ITERATION} of ${MAX_ITERATIONS}.

## Response Format

\`\`\`markdown
### Plan Review (Iteration ${CURRENT_ITERATION})

#### Quality Assessment
**quality: [good / needs-improvement / major-revision]**

#### Section Feedback

**Purpose**: [OK / feedback]
**Scope Exclusions**: [OK / feedback]
**Work Breakdown**: [OK / feedback]
**Implementation Steps**: [OK / feedback]
**Risk Assessment**: [OK / feedback]
**Verification Methods**: [OK / feedback]
**Completion Criteria**: [OK / feedback]

#### Key Issues
1. **[Severity: High/Medium/Low]** [Issue description]
   - Problem: [What's wrong]
   - Suggestion: [How to fix]

#### Positive Aspects
- [What the plan does well]

#### Summary Snapshot
**Decisions confirmed:**
- [Items that are settled]

**Open items:**
- [Items that still need resolution]

**Rejected ideas:**
- [Approaches dismissed, with reason]
\`\`\`

---
quality: [good/needs-improvement/major-revision]
---
EOF

echo "Review prompt prepared: $REVIEW_PROMPT"
echo "Current iteration: $CURRENT_ITERATION"
```

2. Run codex exec to get review:

```bash
export CODEX_SKILL_CONTEXT=1

# Source helpers
HELPERS=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh" ]; then
  HELPERS="${CLAUDE_PLUGIN_ROOT}/scripts/codex-helpers.sh"
elif [ -d ~/.claude/plugins/cache/codex-collab ]; then
  HELPERS=$(ls -td ~/.claude/plugins/cache/codex-collab/codex-collab/*/scripts/codex-helpers.sh 2>/dev/null | head -1)
fi
[ -z "$HELPERS" ] || [ ! -f "$HELPERS" ] && HELPERS="$(pwd)/scripts/codex-helpers.sh"
[ -f "$HELPERS" ] && source "$HELPERS"

TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
REVIEW_PROMPT="$TMP_DIR/collab-planning-review-prompt.txt"
REVIEW_OUTPUT="$TMP_DIR/collab-planning-review-output.md"

# Run codex exec (blocking - output goes to file)
SANDBOX="read-only"
codex_run_exec "$REVIEW_PROMPT" "$REVIEW_OUTPUT" "$SANDBOX"
echo "Review output saved to: $REVIEW_OUTPUT"
```

> **Note:** `codex exec` is blocking. Set Bash tool `timeout` to `min(wait_timeout + 60, 600) * 1000` ms. If Codex unavailable, fallback to claude-only mode.

3. Parse review output and update state file:

Read the review output file, extract quality assessment and feedback, and use Edit tool to append to the state file's iteration log.

**If mode = claude-only:**

Generate review internally:
1. Analyze the plan against the criteria in `plan-review-prompt.md`
2. Provide quality assessment and section feedback
3. Generate summary snapshot
4. Update state file using Edit tool

### Step 5: Process Feedback and Improve Plan

**Parse the quality assessment** from Codex's response:

Extract the `quality` value from the review response (from metadata line `quality: ...` or from the text `**quality: ...**`).

**Generate summary snapshot** and append to state file:

Use Edit tool to append the iteration's snapshot to the state file:

```markdown
### Iteration N Snapshot

**Decisions confirmed:**
- [From Codex's review]

**Open items:**
- [From Codex's review]

**Rejected ideas:**
- [From Codex's review]
```

**If quality = `needs-improvement`:**
1. Address each piece of feedback from Codex
2. Update the plan draft accordingly
3. Update the state file with the revised draft using Edit tool
4. Proceed to Step 6 (iteration control)

**If quality = `good`:**
1. Plan is complete — proceed to Step 7

**If quality = `major-revision`:**
1. Present the feedback to the user via AskUserQuestion
2. Ask: "Codex indicates major revision is needed. Options: (a) Re-draft the plan with Codex's feedback, (b) End planning with current draft"
3. If user chooses (a) → return to Step 3 to re-draft
4. If user chooses (b) → proceed to Step 7 with current draft

### Step 6: Iteration Control

**Update iteration counter:**

```bash
export CODEX_SKILL_CONTEXT=1

TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
PLANNING_DIR="$TMP_DIR/collab-planning"

if [ -z "${STATE_FILE:-}" ]; then
  STATE_FILE=$(ls -t "$PLANNING_DIR"/*.md 2>/dev/null | head -1)
fi

if [ -z "$STATE_FILE" ] || [ ! -f "$STATE_FILE" ]; then
  echo "ERROR: State file not found"
  exit 1
fi

# Read current iteration from state file
ITERATION=$(grep '^iteration:' "$STATE_FILE" | awk '{print $2}')
NEW_ITERATION=$((ITERATION + 1))

# Update iteration counter
awk -v old="iteration: $ITERATION" -v new="iteration: $NEW_ITERATION" \
    '{gsub(old, new); print}' "$STATE_FILE" > "$STATE_FILE.tmp" \
    && mv "$STATE_FILE.tmp" "$STATE_FILE"
echo "Iteration updated to $NEW_ITERATION"
```

**Check iteration limit:**

```bash
export CODEX_SKILL_CONTEXT=1

TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
PLANNING_DIR="$TMP_DIR/collab-planning"

if [ -z "${STATE_FILE:-}" ]; then
  STATE_FILE=$(ls -t "$PLANNING_DIR"/*.md 2>/dev/null | head -1)
fi

CURRENT_ITERATION=$(grep '^iteration:' "$STATE_FILE" | awk '{print $2}')
MAX_ITERATIONS=$(grep '^max_iterations:' "$STATE_FILE" | awk '{print $2}')

if [ "$CURRENT_ITERATION" -ge "$MAX_ITERATIONS" ]; then
  echo "MAX_REACHED=true"
  echo "Maximum iterations ($MAX_ITERATIONS) reached."
else
  echo "MAX_REACHED=false"
  echo "Iteration $CURRENT_ITERATION of $MAX_ITERATIONS. Continuing improvement."
fi
```

**Transition rules:**

| Quality | Max reached? | Next action |
|---------|-------------|-------------|
| `good` | N/A | → Step 7 (finalize) |
| `needs-improvement` | No | → Step 4 (re-submit revised plan) |
| `needs-improvement` | Yes | → Report to user + recommend next step + delegate decision |
| `major-revision` | N/A | → Ask user (Step 5) |
| Any | Yes | → Report current state to user with 1-line recommendation, delegate decision |

**When max_iterations reached:**
- Present the current plan and latest feedback to the user
- Provide a 1-line recommendation (e.g., "Plan covers core requirements; recommend proceeding with implementation noting the open risk items")
- Let the user decide: accept as-is, continue iterating, or abandon

### Step 7: Finalize and Present

**Update state file status:**

```bash
export CODEX_SKILL_CONTEXT=1

TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
PLANNING_DIR="$TMP_DIR/collab-planning"

if [ -z "${STATE_FILE:-}" ]; then
  STATE_FILE=$(ls -t "$PLANNING_DIR"/*.md 2>/dev/null | head -1)
fi

# Update status to completed
awk -v old="status: in_progress" -v new="status: completed" \
    '{gsub(old, new); print}' "$STATE_FILE" > "$STATE_FILE.tmp" \
    && mv "$STATE_FILE.tmp" "$STATE_FILE"

# Update quality
awk -v old="quality: pending" -v new="quality: $FINAL_QUALITY" \
    '{gsub(old, new); print}' "$STATE_FILE" > "$STATE_FILE.tmp" \
    && mv "$STATE_FILE.tmp" "$STATE_FILE"

echo "Planning completed. State file: $STATE_FILE"
```

**Present the final plan to the user:**

Output the completed plan in the fixed template format:

```markdown
## Collaborative Planning Complete

**Task:** [Original task description]
**Iterations:** [N of max]
**Final Quality:** [good / needs-improvement (max reached) / major-revision (user chose to stop)]

---

## Plan: [Title]

### 1. Purpose
[...]

### 2. Scope Exclusions
[...]

### 3. Work Breakdown (WBS)
| # | File | Action | Description |
|---|------|--------|-------------|
| ... | ... | ... | ... |

### 4. Implementation Steps (reference only)
1. [...]

### 5. Risk Assessment
| Risk | Severity | Mitigation |
|------|----------|------------|
| ... | ... | ... |

### 6. Verification Methods
- [ ] [...]

### 7. Completion Criteria
- [ ] [...]

---

### Planning Log
See: tmp/collab-planning/[task-id].md

### Next Steps
- To implement this plan: `/codex-collab [paste plan or reference task-id]`
- To stress-test this plan: `/devils-advocate [key design decision]`
```

**CRITICAL REMINDER: Do NOT proceed to implementation. The plan is the deliverable.**

### Step 8: Cleanup (Optional)

State files are kept for reference. To clean up old plans:

```bash
export CODEX_SKILL_CONTEXT=1

# Remove plans older than 7 days
find "$(pwd)/tmp/collab-planning" -name "*.md" -mtime +7 -delete 2>/dev/null || true
```

## Error Handling

**If Codex unavailable in codex mode:**
- Fall back to claude-only mode (auto-detected when `command -v codex` fails)
- Inform user: "Codex not available, proceeding with Claude-only mode"

**If review times out:**
- Record timeout in state file
- Ask user whether to retry or proceed with current draft

**If early termination requested:**
- Present the current draft as-is
- Note that review was not completed
- Still use the fixed template format

## Compact Recovery

If compacted during planning:

1. Run `TaskList` to see progress
2. Read the state file: `tmp/collab-planning/[task-id].md`
3. Resume from current phase based on state

**State to Phase mapping:**
| State | Resume at |
|-------|-----------|
| iteration: 0, no draft | Step 2 (context) |
| iteration: 0, has draft | Step 4 (submit for review) |
| iteration: 1+ | Step 4 (next review iteration) |
| status: completed | Step 7 (present results) |

## Notes

- Planning state is persisted to survive compaction
- Each planning session gets a unique task ID
- All bash blocks use `awk` for safe text substitution
- Default is 3 iterations but customizable with --max-iterations
- Sandbox is always read-only (Codex reviews only, no file changes)
- **This skill NEVER implements code — it only produces plans**
