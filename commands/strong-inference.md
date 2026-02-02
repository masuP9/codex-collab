---
name: strong-inference
description: Apply Strong Inference methodology to investigate problems with competing hypotheses
argument-hint: [problem description] [--mode codex|claude-only]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, AskUserQuestion
---

# Strong Inference Investigation

Apply the Strong Inference methodology to systematically investigate a problem through competing hypotheses and decisive experiments.

## Problem

$ARGUMENTS

## Workflow Instructions

### Step 0: Load Helper Functions

Source shared helper functions at the beginning of any bash block. **Always set `CODEX_SKILL_CONTEXT=1`** to indicate skill context for the PreToolUse hook:

```bash
# Mark skill context for PreToolUse hook detection
export CODEX_SKILL_CONTEXT=1

# Source helpers (assumes running from plugin root or project root)
HELPERS="${CLAUDE_PLUGIN_ROOT:-$(pwd)}/scripts/codex-helpers.sh"
if [ -f "$HELPERS" ]; then
  source "$HELPERS"
fi
```

### Step 1: Parse Arguments and Initialize

**1. Parse mode from arguments:**

Extract `--mode` option from $ARGUMENTS if present:

```bash
export CODEX_SKILL_CONTEXT=1

# Parse arguments
ARGS="$ARGUMENTS"
MODE_OVERRIDE=""
PROBLEM_DESC=""

# Check for --mode flag
if echo "$ARGS" | grep -qE '\-\-mode\s+(codex|claude-only)'; then
  MODE_OVERRIDE=$(echo "$ARGS" | grep -oE '\-\-mode\s+(codex|claude-only)' | awk '{print $2}')
  # Remove --mode flag from problem description
  PROBLEM_DESC=$(echo "$ARGS" | sed -E 's/--mode\s+(codex|claude-only)//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
else
  PROBLEM_DESC="$ARGS"
fi

echo "Mode override: ${MODE_OVERRIDE:-none}"
echo "Problem: $PROBLEM_DESC"
```

**2. Determine mode (respecting override):**

```bash
export CODEX_SKILL_CONTEXT=1

# Default mode based on environment
DEFAULT_MODE="claude-only"
if [ -n "$TMUX" ] && command -v codex &>/dev/null; then
  DEFAULT_MODE="codex"
fi

# Apply override if specified
if [ -n "$MODE_OVERRIDE" ]; then
  MODE="$MODE_OVERRIDE"
  echo "Mode: $MODE (user specified)"
else
  MODE="$DEFAULT_MODE"
  if [ "$MODE" = "codex" ]; then
    echo "Mode: codex (auto-detected: tmux + Codex available)"
  else
    echo "Mode: claude-only (auto-detected: tmux or Codex not available)"
  fi
fi
```

**3. Generate task ID and initialize state file:**

```bash
export CODEX_SKILL_CONTEXT=1

TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}/strong-inference"
mkdir -p "$TMP_DIR"

TASK_ID="$(date +%Y%m%d-%H%M%S)-$RANDOM"
STATE_FILE="$TMP_DIR/${TASK_ID}.md"

# Create state file with placeholders
cat > "$STATE_FILE" << 'EOFSTATE'
---
schema: strong-inference/v1
task_id: __TASK_ID__
created: __TIMESTAMP__
problem: "__PROBLEM__"
mode: __MODE__
iteration: 0
max_iterations: 10
---

# Investigation: __PROBLEM__

## Hypotheses

(Pending generation)

## Verification Log

| Time | Action | Result |
|------|--------|--------|
EOFSTATE

# Safe replacement using awk (handles special characters in problem description)
awk -v task_id="$TASK_ID" \
    -v timestamp="$(date -Iseconds)" \
    -v mode="$MODE" \
    -v problem="$PROBLEM_DESC" \
    '{
      gsub(/__TASK_ID__/, task_id);
      gsub(/__TIMESTAMP__/, timestamp);
      gsub(/__MODE__/, mode);
      gsub(/__PROBLEM__/, problem);
      print
    }' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"

echo "State file: $STATE_FILE"
echo "Task ID: $TASK_ID"
```

### Step 2: Gather Context

**Create task:**
- subject: "Gather problem context"
- description: "Collect error logs, related code, and reproduction steps"
- activeForm: "Gathering context"

**Collect information:**
1. Ask user for any error messages, logs, or stack traces
2. Identify potentially affected files
3. Read relevant code sections
4. Check recent git changes if applicable

**Update state file with context section using Edit tool** (append after `## Verification Log` table):

```markdown
## Context

### Error Details
[Error messages, stack traces]

### Related Files
- file1.go: Description
- file2.go: Description

### Recent Changes
[Git log or change summary if relevant]
```

### Step 3: Generate Hypotheses

**Task transition:**
- Mark previous task completed
- Create: "Generate competing hypotheses"
- activeForm: "Generating hypotheses"

**Important:** Before running the bash blocks below, ensure you have the following variables from Step 1:
- `$TASK_ID` - The investigation task ID
- `$STATE_FILE` - Path to the state file
- `$MODE` - Either "codex" or "claude-only"
- `$PROBLEM_DESC` - The problem description

**If mode = codex:**

1. Prepare hypothesis request prompt (complete script that reads from state file):

```bash
export CODEX_SKILL_CONTEXT=1

# Set up paths
TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
SI_DIR="$TMP_DIR/strong-inference"
mkdir -p "$TMP_DIR"

# Find the most recent state file if TASK_ID not set
if [ -z "$TASK_ID" ]; then
  # Check how many state files exist
  STATE_COUNT=$(ls "$SI_DIR"/*.md 2>/dev/null | wc -l)
  if [ "$STATE_COUNT" -eq 0 ]; then
    echo "ERROR: No state file found. Run Step 1 first."
    exit 1
  elif [ "$STATE_COUNT" -gt 1 ]; then
    echo "WARNING: Multiple investigation files found ($STATE_COUNT)."
    echo "Available investigations:"
    ls -t "$SI_DIR"/*.md | while read f; do
      PROB=$(awk -F': "' '/^problem:/ {gsub(/"$/, "", $2); print $2}' "$f" | head -c 50)
      echo "  - $(basename "$f" .md): $PROB..."
    done
    echo "Using most recent. Set TASK_ID explicitly to choose a specific one."
  fi
  STATE_FILE=$(ls -t "$SI_DIR"/*.md 2>/dev/null | head -1)
  TASK_ID=$(basename "$STATE_FILE" .md)
else
  STATE_FILE="$SI_DIR/${TASK_ID}.md"
fi

echo "Using state file: $STATE_FILE"
echo "Task ID: $TASK_ID"

# Read problem from state file (handles quotes and special chars)
PROBLEM_DESC=$(awk -F': "' '/^problem:/ {gsub(/"$/, "", $2); print $2}' "$STATE_FILE")

# Extract context section if it exists (between "## Context" and next "##")
CONTEXT_SECTION=$(awk '/^## Context$/,/^## [^C]/' "$STATE_FILE" | grep -v '^## ' || echo "(No context gathered yet)")

HYPOTHESIS_PROMPT="$TMP_DIR/strong-inference-hypothesis-prompt.txt"

cat > "$HYPOTHESIS_PROMPT" << EOF
You are helping investigate a problem using Strong Inference methodology.

## Problem
$PROBLEM_DESC

## Context
$CONTEXT_SECTION

## Task

Generate 2-4 **competing hypotheses** that could explain this problem.

Requirements:
1. **Mutually exclusive**: If one hypothesis is true, the others are less likely
2. **Testable**: Each can be verified or eliminated with specific evidence
3. **Specific**: Clear enough to design a decisive experiment
4. **Prioritized**: Order by likelihood based on available evidence

For each hypothesis, provide:
- A clear statement of the hypothesis
- Why it could be the cause (supporting reasoning)
- What evidence would eliminate it
- Suggested verification approach

## Response Format

\`\`\`markdown
### H1: [Most likely hypothesis]
- Reasoning: [Why this could be the cause]
- Elimination test: [What would prove this wrong]
- Verification: [How to test]

### H2: [Second hypothesis]
...
\`\`\`

---
status: stop
---
EOF

echo "Hypothesis prompt prepared: $HYPOTHESIS_PROMPT"
echo "Problem: $PROBLEM_DESC"
```

2. Get or create Codex pane and send prompt:

```bash
export CODEX_SKILL_CONTEXT=1

HELPERS="${CLAUDE_PLUGIN_ROOT:-$(pwd)}/scripts/codex-helpers.sh"
[ -f "$HELPERS" ] && source "$HELPERS"

TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
PANE_ID_FILE="$TMP_DIR/codex-pane-id"
SANDBOX="read-only"
HYPOTHESIS_PROMPT="$TMP_DIR/strong-inference-hypothesis-prompt.txt"
HYPOTHESIS_OUTPUT="$TMP_DIR/strong-inference-hypothesis-output.md"

# Get or create Codex pane
CODEX_PANE=""
if [ -n "$TMUX" ]; then
  if type codex_get_or_create_pane &>/dev/null; then
    CODEX_PANE=$(codex_get_or_create_pane "$SANDBOX" "$PANE_ID_FILE")
  else
    # Inline fallback: check for existing pane
    if [ -f "$PANE_ID_FILE" ]; then
      STORED_PANE=$(cat "$PANE_ID_FILE")
      PANE_CMD=$(tmux display-message -t "$STORED_PANE" -p '#{pane_current_command}' 2>/dev/null)
      if [ "$PANE_CMD" = "codex" ] || [ "$PANE_CMD" = "node" ]; then
        CODEX_PANE="$STORED_PANE"
      fi
    fi
    # Launch new if not found
    if [ -z "$CODEX_PANE" ]; then
      ORIGINAL_PANE=$(tmux display-message -p '#{pane_id}')
      tmux split-window -h -d -c "$(pwd)" "codex -s $SANDBOX"
      sleep 3
      CODEX_PANE=$(tmux list-panes -F '#{pane_id}' | grep -v "^${ORIGINAL_PANE}$" | tail -1)
      echo "$CODEX_PANE" > "$PANE_ID_FILE"
      tmux select-pane -t "$ORIGINAL_PANE"
    fi
  fi
fi

# Graceful fallback to claude-only mode (not exit)
if [ -z "$CODEX_PANE" ]; then
  echo "WARNING: No Codex pane available. Switching to claude-only mode."
  echo "MODE_SWITCHED=claude-only"
  # Signal to the LLM to use claude-only mode for this step
  exit 0
fi

echo "Using Codex pane: $CODEX_PANE"

# Capture state before sending
BEFORE_CONTENT=$(tmux capture-pane -t "$CODEX_PANE" -p -S -5000)
if type codex_hash_content &>/dev/null; then
  BEFORE_HASH=$(echo "$BEFORE_CONTENT" | codex_hash_content)
else
  BEFORE_HASH=$(echo "$BEFORE_CONTENT" | md5sum 2>/dev/null | awk '{print $1}')
fi

# Send prompt
MARKER_ID="$(date +%s)-$RANDOM"
END_MARKER="<<RESPONSE_END_${MARKER_ID}>>"

if type codex_send_prompt_chunked &>/dev/null; then
  END_MARKER=$(codex_send_prompt_chunked "$CODEX_PANE" "$(cat "$HYPOTHESIS_PROMPT")")
else
  # Inline fallback
  PROMPT_CONTENT=$(cat "$HYPOTHESIS_PROMPT")
  FULL_PROMPT="${PROMPT_CONTENT}

When finished, output exactly: ${END_MARKER}"

  tmux send-keys -t "$CODEX_PANE" C-u
  sleep 0.1
  TEMP_FILE="$TMP_DIR/codex-prompt-$$"
  echo "$FULL_PROMPT" > "$TEMP_FILE"
  tmux load-buffer "$TEMP_FILE"
  tmux paste-buffer -t "$CODEX_PANE"
  sleep 0.5
  tmux send-keys -t "$CODEX_PANE" Enter
  rm -f "$TEMP_FILE"
fi

echo "Prompt sent to Codex pane: $CODEX_PANE"
echo "Completion marker: $END_MARKER"
echo "BEFORE_HASH=$BEFORE_HASH"

# Save state for next step (task-specific to avoid conflicts)
SI_STATE_FILE="$TMP_DIR/strong-inference-state-${TASK_ID}.env"
cat > "$SI_STATE_FILE" << EOF
TASK_ID=$TASK_ID
STATE_FILE=$STATE_FILE
CODEX_PANE=$CODEX_PANE
END_MARKER=$END_MARKER
BEFORE_HASH=$BEFORE_HASH
EOF
echo "State saved to: $SI_STATE_FILE"
```

3. Wait for Codex response:

```bash
export CODEX_SKILL_CONTEXT=1

HELPERS="${CLAUDE_PLUGIN_ROOT:-$(pwd)}/scripts/codex-helpers.sh"
[ -f "$HELPERS" ] && source "$HELPERS"

TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
SI_DIR="$TMP_DIR/strong-inference"

# Load state from previous step (task-specific file)
# If TASK_ID is set, use that; otherwise find most recent state file
if [ -n "$TASK_ID" ]; then
  SI_STATE_FILE="$TMP_DIR/strong-inference-state-${TASK_ID}.env"
else
  SI_STATE_FILE=$(ls -t "$TMP_DIR"/strong-inference-state-*.env 2>/dev/null | head -1)
fi

if [ -z "$SI_STATE_FILE" ] || [ ! -f "$SI_STATE_FILE" ]; then
  echo "ERROR: State file not found. Run step 2 first."
  exit 1
fi

source "$SI_STATE_FILE"
echo "Loaded state for task: $TASK_ID"

WAIT_TIMEOUT=180

if type codex_wait_completion &>/dev/null; then
  CODEX_WAIT_TIMEOUT="$WAIT_TIMEOUT"
  codex_wait_completion "$CODEX_PANE" "$END_MARKER" "$BEFORE_HASH"
else
  # Inline fallback: poll for marker or idle
  COMPLETED=false
  POLL_INTERVAL=2
  IDLE_THRESHOLD=5
  IDLE_COUNT=0
  LAST_HASH="$BEFORE_HASH"

  for i in $(seq 1 $((WAIT_TIMEOUT / POLL_INTERVAL))); do
    CURRENT_OUTPUT=$(tmux capture-pane -t "$CODEX_PANE" -p -S -5000)
    CURRENT_HASH=$(echo "$CURRENT_OUTPUT" | md5sum 2>/dev/null | awk '{print $1}')

    if echo "$CURRENT_OUTPUT" | grep -qF "$END_MARKER"; then
      echo "Codex response completed (marker found)"
      COMPLETED=true
      break
    fi

    if [ "$CURRENT_HASH" = "$LAST_HASH" ]; then
      IDLE_COUNT=$((IDLE_COUNT + 1))
      if [ "$IDLE_COUNT" -ge "$IDLE_THRESHOLD" ]; then
        if echo "$CURRENT_OUTPUT" | tail -5 | grep -qE '^\s*›|^>'; then
          echo "Codex appears idle"
          COMPLETED=true
          break
        fi
      fi
    else
      IDLE_COUNT=0
      LAST_HASH="$CURRENT_HASH"
    fi

    sleep $POLL_INTERVAL
  done

  [ "$COMPLETED" = false ] && echo "Warning: Timeout after ${WAIT_TIMEOUT}s"
fi

# Capture output
HYPOTHESIS_OUTPUT="$TMP_DIR/strong-inference-hypothesis-output.md"
tmux capture-pane -t "$CODEX_PANE" -p -S -5000 > "$HYPOTHESIS_OUTPUT"
echo "Output captured to: $HYPOTHESIS_OUTPUT"
```

4. Parse hypotheses from response and update state file:

Read the hypothesis output file, extract the hypotheses section (between markdown code blocks), and use the Edit tool to replace `(Pending generation)` in the state file with the actual hypotheses.

**If mode = claude-only:**

Generate hypotheses directly using reasoning:
1. Analyze the problem and context
2. Generate 2-4 competing hypotheses
3. Rank by likelihood
4. Update state file using Edit tool

### Step 4: Design Verification Tests

**Task transition:**
- Create: "Design verification experiments"
- activeForm: "Designing experiments"

For each hypothesis, design a "killer experiment":

1. **Prioritize by:**
   - Ease of execution (quick wins first)
   - Discriminating power (can eliminate multiple hypotheses)
   - Safety (non-destructive tests first)

2. **For each experiment, define:**
   - What to check/run
   - Expected result if hypothesis is true
   - Expected result if hypothesis is false
   - Commands or code inspection needed

3. **Update state file using Edit tool:**

```markdown
### H1: [Hypothesis]
- Status: [?] Pending
- Test: [Specific verification to perform]
- If true: [Expected observation]
- If false: [Expected observation]
- Priority: High/Medium/Low
```

### Step 5: Execute Verifications

**Task transition:**
- Create: "Execute verification experiments"
- activeForm: "Verifying hypotheses"

Execute tests in priority order:

**For each verification:**

1. **Announce action:**
```
Verifying H1: [Hypothesis name]
Test: [What we're checking]
```

2. **Execute verification** (code reading, log analysis, test running):
   - Use Read tool for code inspection
   - Use Grep for log/pattern search
   - Use Bash for running tests (with user confirmation)

3. **Record result in state file:**

```bash
export CODEX_SKILL_CONTEXT=1

# Set variables for this step
TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
SI_DIR="$TMP_DIR/strong-inference"

# Find most recent state file if not set
if [ -z "$STATE_FILE" ]; then
  STATE_FILE=$(ls -t "$SI_DIR"/*.md 2>/dev/null | head -1)
fi

TIMESTAMP=$(date +%H:%M)
# Replace these with actual values when running:
ACTION="Checked [specific thing]"
RESULT="Found [specific result]"

# Append to verification log
echo "| $TIMESTAMP | $ACTION | $RESULT |" >> "$STATE_FILE"
echo "Logged to: $STATE_FILE"
```

4. **Update hypothesis status** using Edit tool:
   - `[X]` Eliminated - evidence contradicts
   - `[!]` Supported - evidence aligns
   - `[?]` Pending - not yet conclusive

5. **Safety check before destructive operations:**

Use AskUserQuestion tool before running tests or modifying files:
- "This verification requires running tests. Proceed?"
- "This will add debug logging to file.go. Approve?"

### Step 6: Analyze and Iterate

After each verification round:

1. **Display current status:**
```
Strong Inference Investigation
==============================
Problem: [Problem description]

Hypotheses:
  [X] H1: [Hypothesis] - Eliminated (evidence: ...)
  [!] H2: [Hypothesis] - Supported (evidence: ...)
  [?] H3: [Hypothesis] - Pending

Iteration: 2/10
```

2. **Check termination conditions:**
   - One hypothesis strongly supported → Go to Step 7
   - All hypotheses eliminated → Generate new hypotheses (return to Step 3)
   - max_iterations reached → Report inconclusive and ask user

3. **If continuing:**
   - Refine remaining hypotheses based on new evidence
   - Design next verification
   - Return to Step 5

**Iteration tracking:**

```bash
export CODEX_SKILL_CONTEXT=1

# Set variables for this step
TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
SI_DIR="$TMP_DIR/strong-inference"

# Find most recent state file if not set
if [ -z "$STATE_FILE" ]; then
  STATE_FILE=$(ls -t "$SI_DIR"/*.md 2>/dev/null | head -1)
fi

if [ -z "$STATE_FILE" ] || [ ! -f "$STATE_FILE" ]; then
  echo "ERROR: State file not found"
  exit 1
fi

# Read current iteration from state file
ITERATION=$(grep '^iteration:' "$STATE_FILE" | awk '{print $2}')
MAX_ITER=$(grep '^max_iterations:' "$STATE_FILE" | awk '{print $2}')
NEW_ITER=$((ITERATION + 1))

if [ "$NEW_ITER" -ge "$MAX_ITER" ]; then
  echo "Max iterations reached ($MAX_ITER)"
else
  # Use awk for safe replacement
  awk -v old="iteration: $ITERATION" -v new="iteration: $NEW_ITER" \
      '{gsub(old, new); print}' "$STATE_FILE" > "$STATE_FILE.tmp" \
      && mv "$STATE_FILE.tmp" "$STATE_FILE"
  echo "Iteration updated to $NEW_ITER"
fi
```

### Step 7: Conclude Investigation

**Task transition:**
- Create: "Summarize findings and propose solution"
- activeForm: "Concluding investigation"

**If mode = codex:**

Request Codex review of findings:

```bash
export CODEX_SKILL_CONTEXT=1

# Set variables for this step
TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
SI_DIR="$TMP_DIR/strong-inference"
REVIEW_PROMPT="$TMP_DIR/strong-inference-review-prompt.txt"

# Find most recent state file if not set
if [ -z "$STATE_FILE" ]; then
  STATE_FILE=$(ls -t "$SI_DIR"/*.md 2>/dev/null | head -1)
fi

if [ -z "$STATE_FILE" ] || [ ! -f "$STATE_FILE" ]; then
  echo "ERROR: State file not found"
  exit 1
fi

# Read state file content
STATE_CONTENT=$(cat "$STATE_FILE")

cat > "$REVIEW_PROMPT" << EOF
Review the Strong Inference investigation results.

## Investigation Summary
$STATE_CONTENT

## Task

1. Validate the conclusion based on evidence
2. Assess confidence level (High/Medium/Low)
3. Suggest specific fix for the root cause
4. Recommend prevention measures

## Response Format

\`\`\`markdown
## Review

### Confidence Assessment
[High/Medium/Low] - [Reasoning]

### Recommended Fix
[Specific code changes or actions]

### Prevention
[How to avoid similar issues]
\`\`\`

---
status: stop
verdict: pass
---
EOF

echo "Review prompt prepared: $REVIEW_PROMPT"
```

Then send to Codex using the same pattern as Step 3 (get pane, send prompt, wait, capture output).

**Report to user:**

```markdown
## Investigation Complete

**Problem:** [Original problem]

**Root Cause:** [Confirmed hypothesis]
**Confidence:** High/Medium/Low

### Evidence Trail
1. [First evidence point]
2. [Second evidence point]
3. [Third evidence point]

### Recommended Fix
[Specific solution based on root cause]

### Prevention
[Suggestions to avoid similar issues]

### Investigation Log
See: tmp/strong-inference/[task-id].md
```

### Step 8: Cleanup (Optional)

State files are kept for reference. To clean up old investigations:

```bash
export CODEX_SKILL_CONTEXT=1

# Remove investigations older than 7 days
find "$(pwd)/tmp/strong-inference" -name "*.md" -mtime +7 -delete 2>/dev/null || true
```

## Error Handling

**If Codex unavailable in codex mode:**
- Fall back to claude-only mode
- Inform user: "Codex not available, proceeding with Claude-only mode"

**If verification times out:**
- Record timeout in log
- Ask user whether to retry or skip

**If all hypotheses eliminated:**
- Summarize what was learned
- Ask user for additional context
- Generate new hypotheses based on evidence

## Compact Recovery

If compacted during investigation:

1. Run `TaskList` to see progress
2. Read the state file: `tmp/strong-inference/[task-id].md`
3. Resume from current phase based on state

**State to Phase mapping:**
| State | Resume at |
|-------|-----------|
| "Pending generation" in Hypotheses | Step 3 |
| Hypotheses listed, all [?] | Step 4 or 5 |
| Mix of [X], [!], [?] | Step 5 or 6 |
| One [!] with strong evidence | Step 7 |

## Notes

- Hypothesis tree is persisted to survive compaction
- Each investigation gets a unique task ID
- Verification log provides audit trail
- Default max_iterations is 10 to prevent runaway investigations
- Always confirm before destructive operations
- All bash blocks use `awk` for safe text substitution (no sed escaping issues)
