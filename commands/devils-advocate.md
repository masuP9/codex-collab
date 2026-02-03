---
name: devils-advocate
description: Devil's Advocate methodology to stress-test hypotheses and designs through structured debate
argument-hint: [proposal] [--mode codex|claude-only] [--max-rounds N]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, AskUserQuestion
---

# Devil's Advocate Review

Apply the Devil's Advocate methodology to stress-test a hypothesis or design proposal through structured adversarial debate.

## Proposal

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

Extract `--mode` and `--max-rounds` options from $ARGUMENTS if present:

```bash
export CODEX_SKILL_CONTEXT=1

# Parse arguments
ARGS="$ARGUMENTS"
MODE_OVERRIDE=""
MAX_ROUNDS_OVERRIDE=""
PROPOSAL_DESC=""

# Check for --mode flag
if echo "$ARGS" | grep -qE '\-\-mode\s+(codex|claude-only)'; then
  MODE_OVERRIDE=$(echo "$ARGS" | grep -oE '\-\-mode\s+(codex|claude-only)' | awk '{print $2}')
  ARGS=$(echo "$ARGS" | sed -E 's/--mode\s+(codex|claude-only)//')
fi

# Check for --max-rounds flag
if echo "$ARGS" | grep -qE '\-\-max-rounds\s+[0-9]+'; then
  MAX_ROUNDS_OVERRIDE=$(echo "$ARGS" | grep -oE '\-\-max-rounds\s+[0-9]+' | awk '{print $2}')
  ARGS=$(echo "$ARGS" | sed -E 's/--max-rounds\s+[0-9]+//')
fi

# Remaining is the proposal description
PROPOSAL_DESC=$(echo "$ARGS" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

echo "Mode override: ${MODE_OVERRIDE:-none}"
echo "Max rounds override: ${MAX_ROUNDS_OVERRIDE:-none}"
echo "Proposal: $PROPOSAL_DESC"
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

# Set max rounds (default: 3)
MAX_ROUNDS="${MAX_ROUNDS_OVERRIDE:-3}"
echo "Max rounds: $MAX_ROUNDS"
```

**3. Generate task ID and initialize state file:**

```bash
export CODEX_SKILL_CONTEXT=1

TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}/devils-advocate"
mkdir -p "$TMP_DIR"

TASK_ID="$(date +%Y%m%d-%H%M%S)-$RANDOM"
STATE_FILE="$TMP_DIR/${TASK_ID}.md"

# Create state file with placeholders
cat > "$STATE_FILE" << 'EOFSTATE'
---
schema: devils-advocate/v1
task_id: __TASK_ID__
created: __TIMESTAMP__
proposal: "__PROPOSAL__"
mode: __MODE__
round: 0
max_rounds: __MAX_ROUNDS__
status: in_progress
verdict: pending
---

# Red Team Review: __PROPOSAL__

## Overview

**Proposal:** __PROPOSAL__
**Mode:** __MODE__
**Max Rounds:** __MAX_ROUNDS__

## Debate Log

EOFSTATE

# Safe replacement using awk (handles special characters in proposal description)
awk -v task_id="$TASK_ID" \
    -v timestamp="$(date -Iseconds)" \
    -v mode="$MODE" \
    -v max_rounds="$MAX_ROUNDS" \
    -v proposal="$PROPOSAL_DESC" \
    '{
      gsub(/__TASK_ID__/, task_id);
      gsub(/__TIMESTAMP__/, timestamp);
      gsub(/__MODE__/, mode);
      gsub(/__MAX_ROUNDS__/, max_rounds);
      gsub(/__PROPOSAL__/, proposal);
      print
    }' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"

echo "State file: $STATE_FILE"
echo "Task ID: $TASK_ID"
```

### Step 2: Gather Context

**Create task:**
- subject: "Gather proposal context"
- description: "Collect design documents, related code, and context for the proposal"
- activeForm: "Gathering context"

**Collect information:**
1. Ask user for any design documents, specifications, or references
2. Identify potentially affected files or components
3. Read relevant code sections
4. Understand the current state and the proposed change

**Update state file with context section using Edit tool** (append after `## Debate Log`):

```markdown
## Context

### Proposal Summary
[Brief summary of the proposal]

### Related Files
- file1.ts: Description
- file2.ts: Description

### Current State
[Description of how things work currently]

### Proposed Change
[Description of what the proposal aims to change]
```

### Step 3-5: Debate Rounds

Execute debate rounds. Each round follows this pattern:

**Round Structure:**
1. **Blue Team (Claude)**: Present/defend the proposal
2. **Red Team (Codex/Claude)**: Critique and find weaknesses

**For each round (1 to max_rounds):**

**Task transition:**
- Mark previous task completed
- Create: "Execute Round N debate"
- activeForm: "Debating round N"

**Important:** Before running the bash blocks below, ensure you have the following variables from Step 1:
- `$TASK_ID` - The debate task ID
- `$STATE_FILE` - Path to the state file
- `$MODE` - Either "codex" or "claude-only"
- `$MAX_ROUNDS` - Maximum number of rounds
- `$PROPOSAL_DESC` - The proposal description

#### Blue Team Phase (Claude)

**Round 1:** Present the proposal with:
- Clear statement of the proposal
- Key benefits and rationale
- Anticipated concerns and mitigations

**Round 2+:** Respond to previous Red Team feedback:
- Address each critique
- Present refined proposal
- Acknowledge valid concerns

Update state file with Blue Team section using Edit tool:

```markdown
### Round N

#### Blue Team (Claude)

**Position:**
[Proposal statement or response to previous critique]

**Key Points:**
1. [Point 1]
2. [Point 2]
3. [Point 3]

**Response to Concerns:**
[If Round 2+, address previous Red Team feedback]
```

#### Red Team Phase

**If mode = codex:**

1. Prepare critique request prompt:

```bash
export CODEX_SKILL_CONTEXT=1

# Set up paths
TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
DA_DIR="$TMP_DIR/devils-advocate"
mkdir -p "$TMP_DIR"

# Find the most recent state file if TASK_ID not set
if [ -z "$TASK_ID" ]; then
  STATE_COUNT=$(ls "$DA_DIR"/*.md 2>/dev/null | wc -l)
  if [ "$STATE_COUNT" -eq 0 ]; then
    echo "ERROR: No state file found. Run Step 1 first."
    exit 1
  elif [ "$STATE_COUNT" -gt 1 ]; then
    echo "WARNING: Multiple debate files found ($STATE_COUNT)."
    echo "Using most recent. Set TASK_ID explicitly to choose a specific one."
  fi
  STATE_FILE=$(ls -t "$DA_DIR"/*.md 2>/dev/null | head -1)
  TASK_ID=$(basename "$STATE_FILE" .md)
else
  STATE_FILE="$DA_DIR/${TASK_ID}.md"
fi

echo "Using state file: $STATE_FILE"
echo "Task ID: $TASK_ID"

# Read current round, max_rounds, and proposal from state file
CURRENT_ROUND=$(grep '^round:' "$STATE_FILE" | awk '{print $2}')
MAX_ROUNDS=$(grep '^max_rounds:' "$STATE_FILE" | awk '{print $2}')
PROPOSAL_DESC=$(awk -F': "' '/^proposal:/ {gsub(/"$/, "", $2); print $2}' "$STATE_FILE")

# Increment round for the upcoming Red Team phase (round starts at 0, first critique is Round 1)
CURRENT_ROUND=$((CURRENT_ROUND + 1))

# Extract debate history
DEBATE_HISTORY=$(awk '/^## Debate Log$/,/^## Verdict/' "$STATE_FILE" | grep -v '^## ' || echo "(No debate history yet)")

CRITIQUE_PROMPT="$TMP_DIR/devils-advocate-critique-prompt.txt"

# Source helpers for language directive
HELPERS="${CLAUDE_PLUGIN_ROOT:-$(pwd)}/scripts/codex-helpers.sh"
[ -f "$HELPERS" ] && source "$HELPERS"

# Get language setting from config (default: en)
SETTINGS_FILE=".claude/codex-collab.local.md"
if [ -f "$SETTINGS_FILE" ]; then
  LANGUAGE=$(awk '/^language:/ {print $2}' "$SETTINGS_FILE" 2>/dev/null || echo "en")
else
  LANGUAGE="en"
fi

# Get language directive (empty for English)
LANG_DIRECTIVE=$(codex_get_language_directive "$LANGUAGE")

cat > "$CRITIQUE_PROMPT" << EOF
${LANG_DIRECTIVE}You are the Red Team (Devil's Advocate) in a structured debate.

## Your Role

Your job is to **critique and challenge** the proposal below. Be thorough but fair.
Focus on finding:
- Logical flaws or gaps in reasoning
- Technical risks or implementation challenges
- Edge cases not considered
- Scalability, security, or maintainability concerns
- Alternative approaches that might be better

## Proposal

$PROPOSAL_DESC

## Debate History

$DEBATE_HISTORY

## Task

Provide a structured critique of the Blue Team's position.

**Round ${CURRENT_ROUND} Critique Requirements:**
$(if [ "$CURRENT_ROUND" -eq 1 ]; then
  echo "- Initial critique: Identify major weaknesses and risks"
  echo "- List at least 3 concerns with severity levels (Critical/High/Medium/Low)"
  echo "- Suggest alternatives or improvements"
elif [ "$CURRENT_ROUND" -lt "$MAX_ROUNDS" ]; then
  echo "- Re-evaluate based on Blue Team's responses"
  echo "- Acknowledge points that have been adequately addressed"
  echo "- Identify remaining or new concerns"
  echo "- Prioritize the most important unresolved issues"
else
  echo "- Final evaluation: Assess overall proposal quality"
  echo "- Provide final verdict: APPROVE / CONDITIONAL / REJECT"
  echo "- List any conditions for approval (if CONDITIONAL)"
  echo "- Summarize key risks that remain"
fi)

## Response Format

\`\`\`markdown
### Red Team Critique (Round ${CURRENT_ROUND})

#### Key Concerns
1. **[Severity: Critical/High/Medium/Low]** [Concern title]
   - Issue: [Description]
   - Impact: [Potential consequences]
   - Suggestion: [Recommended mitigation]

2. ...

#### $(if [ "$CURRENT_ROUND" -lt "$MAX_ROUNDS" ]; then echo "Open Questions"; else echo "Final Assessment"; fi)
[Questions for Blue Team OR Final verdict with reasoning]

$(if [ "$CURRENT_ROUND" -eq "$MAX_ROUNDS" ]; then
cat << 'VERDICT'
#### Verdict

**Decision:** [APPROVE / CONDITIONAL / REJECT]

**Reasoning:**
[Explanation of the verdict]

**Conditions (if CONDITIONAL):**
- [Condition 1]
- [Condition 2]

**Remaining Risks:**
- [Risk 1]
- [Risk 2]
VERDICT
fi)
\`\`\`

---
status: stop
$(if [ "$CURRENT_ROUND" -eq "$MAX_ROUNDS" ]; then echo "verdict: [APPROVE/CONDITIONAL/REJECT]"; fi)
---
EOF

echo "Critique prompt prepared: $CRITIQUE_PROMPT"
echo "Current round: $CURRENT_ROUND"
```

2. Get or create Codex pane and send prompt:

```bash
export CODEX_SKILL_CONTEXT=1

HELPERS="${CLAUDE_PLUGIN_ROOT:-$(pwd)}/scripts/codex-helpers.sh"
[ -f "$HELPERS" ] && source "$HELPERS"

TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
DA_DIR="$TMP_DIR/devils-advocate"
mkdir -p "$DA_DIR"
PANE_ID_FILE="$TMP_DIR/codex-pane-id"
SANDBOX="read-only"
CRITIQUE_PROMPT="$TMP_DIR/devils-advocate-critique-prompt.txt"

# Get or create Codex pane
CODEX_PANE=""
if [ -n "$TMUX" ]; then
  CODEX_PANE=$(codex_get_or_create_pane "$SANDBOX" "$PANE_ID_FILE")
fi

# Graceful fallback to claude-only mode (not exit)
if [ -z "$CODEX_PANE" ]; then
  echo "WARNING: No Codex pane available. Switching to claude-only mode."
  echo "MODE_SWITCHED=claude-only"
  exit 0
fi

echo "Using Codex pane: $CODEX_PANE"

# Capture state before sending
BEFORE_CONTENT=$(tmux capture-pane -t "$CODEX_PANE" -p -S -5000)
BEFORE_HASH=$(echo "$BEFORE_CONTENT" | codex_hash_content)

# Send prompt using chunked method
WAIT_TIMEOUT="${CODEX_WAIT_TIMEOUT:-180}"
END_MARKER=$(codex_send_prompt_chunked "$CODEX_PANE" "$(cat "$CRITIQUE_PROMPT")")
echo "Prompt sent to Codex pane: $CODEX_PANE"
echo "Completion marker: $END_MARKER"

# Save state for next step
DA_STATE_FILE="$TMP_DIR/devils-advocate-state-${TASK_ID}.env"
cat > "$DA_STATE_FILE" << EOF
TASK_ID=$TASK_ID
STATE_FILE=$STATE_FILE
CODEX_PANE=$CODEX_PANE
END_MARKER=$END_MARKER
BEFORE_HASH=$BEFORE_HASH
CURRENT_ROUND=$CURRENT_ROUND
EOF
echo "State saved to: $DA_STATE_FILE"
```

3. Wait for Codex response:

```bash
export CODEX_SKILL_CONTEXT=1

HELPERS="${CLAUDE_PLUGIN_ROOT:-$(pwd)}/scripts/codex-helpers.sh"
[ -f "$HELPERS" ] && source "$HELPERS"

TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
DA_DIR="$TMP_DIR/devils-advocate"

# Load state from previous step
if [ -n "$TASK_ID" ]; then
  DA_STATE_FILE="$TMP_DIR/devils-advocate-state-${TASK_ID}.env"
else
  DA_STATE_FILE=$(ls -t "$TMP_DIR"/devils-advocate-state-*.env 2>/dev/null | head -1)
fi

if [ -z "$DA_STATE_FILE" ] || [ ! -f "$DA_STATE_FILE" ]; then
  echo "ERROR: State file not found. Run previous step first."
  exit 1
fi

source "$DA_STATE_FILE"
echo "Loaded state for task: $TASK_ID"

# Wait for completion
CRITIQUE_OUTPUT="$TMP_DIR/devils-advocate-critique-output.md"
CODEX_WAIT_TIMEOUT=180
codex_wait_completion "$CODEX_PANE" "$END_MARKER" "$BEFORE_HASH"

# Capture output
codex_capture_output "$CODEX_PANE" "$CRITIQUE_OUTPUT"
echo "Output captured to: $CRITIQUE_OUTPUT"
```

4. Parse critique from response and update state file:

Read the critique output file, extract the critique section, and use the Edit tool to append to the state file's debate log.

**If mode = claude-only:**

Generate critique directly using reasoning:
1. Analyze the proposal and previous debate history
2. Identify weaknesses, risks, and concerns
3. Provide structured critique
4. If final round, provide verdict
5. Update state file using Edit tool

**After Red Team phase, update round counter:**

```bash
export CODEX_SKILL_CONTEXT=1

# Set variables for this step
TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
DA_DIR="$TMP_DIR/devils-advocate"

# Find most recent state file if not set
if [ -z "$STATE_FILE" ]; then
  STATE_FILE=$(ls -t "$DA_DIR"/*.md 2>/dev/null | head -1)
fi

if [ -z "$STATE_FILE" ] || [ ! -f "$STATE_FILE" ]; then
  echo "ERROR: State file not found"
  exit 1
fi

# Read current round from state file
ROUND=$(grep '^round:' "$STATE_FILE" | awk '{print $2}')
NEW_ROUND=$((ROUND + 1))

# Update round counter
awk -v old="round: $ROUND" -v new="round: $NEW_ROUND" \
    '{gsub(old, new); print}' "$STATE_FILE" > "$STATE_FILE.tmp" \
    && mv "$STATE_FILE.tmp" "$STATE_FILE"
echo "Round updated to $NEW_ROUND"
```

**Check if debate should continue:**

```bash
export CODEX_SKILL_CONTEXT=1

TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
DA_DIR="$TMP_DIR/devils-advocate"

if [ -z "$STATE_FILE" ]; then
  STATE_FILE=$(ls -t "$DA_DIR"/*.md 2>/dev/null | head -1)
fi

CURRENT_ROUND=$(grep '^round:' "$STATE_FILE" | awk '{print $2}')
MAX_ROUNDS=$(grep '^max_rounds:' "$STATE_FILE" | awk '{print $2}')

if [ "$CURRENT_ROUND" -ge "$MAX_ROUNDS" ]; then
  echo "DEBATE_COMPLETE=true"
  echo "Final round completed. Proceeding to conclusion."
else
  echo "DEBATE_COMPLETE=false"
  echo "Round $CURRENT_ROUND of $MAX_ROUNDS complete. Continuing debate."
fi
```

### Step 6: Conclude and Report

**Task transition:**
- Create: "Generate final report"
- activeForm: "Generating report"

**Extract verdict from final Red Team response:**

```bash
export CODEX_SKILL_CONTEXT=1

TMP_DIR="$(pwd)/${CODEX_TMP_DIR:-tmp}"
DA_DIR="$TMP_DIR/devils-advocate"

if [ -z "$STATE_FILE" ]; then
  STATE_FILE=$(ls -t "$DA_DIR"/*.md 2>/dev/null | head -1)
fi

# Extract verdict from the state file
VERDICT=$(grep -A5 '#### Verdict' "$STATE_FILE" | grep -E 'Decision:|verdict:' | head -1 | grep -oE '(APPROVE|CONDITIONAL|REJECT)' || echo "UNKNOWN")

echo "Final verdict: $VERDICT"

# Update state file verdict
awk -v old="verdict: pending" -v new="verdict: $VERDICT" \
    '{gsub(old, new); print}' "$STATE_FILE" > "$STATE_FILE.tmp" \
    && mv "$STATE_FILE.tmp" "$STATE_FILE"

# Update status to completed
awk -v old="status: in_progress" -v new="status: completed" \
    '{gsub(old, new); print}' "$STATE_FILE" > "$STATE_FILE.tmp" \
    && mv "$STATE_FILE.tmp" "$STATE_FILE"

echo "State file updated with verdict: $VERDICT"
```

**Report to user:**

```markdown
## Devil's Advocate Review Complete

**Proposal:** [Original proposal]

**Verdict:** [APPROVE / CONDITIONAL / REJECT]

### Summary

[Brief summary of the debate outcome]

### Key Concerns Raised
1. [Concern 1] - [Status: Addressed/Partially Addressed/Unresolved]
2. [Concern 2] - [Status]
3. [Concern 3] - [Status]

### Conditions (if CONDITIONAL)
- [Condition 1]
- [Condition 2]

### Remaining Risks
- [Risk 1]
- [Risk 2]

### Recommendations
[Next steps based on the verdict]

### Debate Log
See: tmp/devils-advocate/[task-id].md
```

### Step 7: Cleanup (Optional)

State files are kept for reference. To clean up old debates:

```bash
export CODEX_SKILL_CONTEXT=1

# Remove debates older than 7 days
find "$(pwd)/tmp/devils-advocate" -name "*.md" -mtime +7 -delete 2>/dev/null || true
```

## Evaluation Criteria

The Red Team uses these criteria for the final verdict:

### APPROVE
- No critical or high-severity issues remain
- All major concerns have been adequately addressed
- Implementation is feasible and reasonably safe
- Benefits clearly outweigh remaining risks

### CONDITIONAL
- Implementation can proceed with specific conditions
- Some concerns remain but are manageable
- Specific mitigations or follow-up actions required
- Benefits justify accepting controlled risks

### REJECT
- Critical flaws that fundamentally undermine the proposal
- Major risks that cannot be adequately mitigated
- Alternative approaches are clearly superior
- Implementation would cause significant harm

## Error Handling

**If Codex unavailable in codex mode:**
- Fall back to claude-only mode
- Inform user: "Codex not available, proceeding with Claude-only mode"

**If debate times out:**
- Record timeout in log
- Ask user whether to continue or conclude early

**If early termination requested:**
- Summarize debate so far
- Provide interim assessment
- Note that full evaluation was not completed

## Compact Recovery

If compacted during debate:

1. Run `TaskList` to see progress
2. Read the state file: `tmp/devils-advocate/[task-id].md`
3. Resume from current phase based on state

**State to Phase mapping:**
| State | Resume at |
|-------|-----------|
| round: 0 | Step 3 (Round 1) |
| round: 1 | Step 3 (Round 2) |
| round: 2 | Step 3 (Round 3) |
| round: 3+ | Step 6 (Conclusion) |

## Notes

- Debate state is persisted to survive compaction
- Each debate gets a unique task ID
- All bash blocks use `awk` for safe text substitution
- Default is 3 rounds but can be customized with --max-rounds
- Red Team should be constructive, not adversarial for its own sake
