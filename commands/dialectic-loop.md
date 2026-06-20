---
name: dialectic-loop
description: Validate and refine an empirical claim by deriving predictions and testing them against a real corpus (deductive → inductive → arbiter loop)
argument-hint: [claim] [--corpus PATH/GLOB] [--mode codex|claude-only] [--max-rounds N] [--rotate]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, AskUserQuestion, mcp__codex__codex, mcp__codex__codex-reply
---

# Dialectic Loop

Run Peirce's inquiry cycle (abduction → deduction → induction) across three roles to validate and refine a claim about reality against real data. See `skills/dialectic-loop/SKILL.md` for the full methodology.

## Claim

$ARGUMENTS

## Workflow Instructions

### Step 0: Load Helper Functions

Source shared helpers at the start of any bash block. **Always set `CODEX_SKILL_CONTEXT=1`** for the PreToolUse hook:

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
[ -f "$HELPERS" ] && source "$HELPERS" || echo "Error: codex-helpers.sh not found" >&2
```

### Step 1: Parse Arguments and Initialize

1. **Parse options** from `$ARGUMENTS`: `--corpus <path|glob>`, `--mode <codex|claude-only>`, `--max-rounds <N>`, `--rotate`. The remainder is the claim.
2. **Determine mode**: default `codex` when `command -v codex` succeeds, else `claude-only`; honor `--mode` override. Default `--max-rounds` is 3.
3. **Generate task id and state file** at `tmp/dialectic-loop/<task-id>.md` using the `dialectic-loop/v1` schema (see SKILL.md → State File). Use `awk` for safe substitution of the claim/corpus into the template. Confirm the corpus path with the user if `--corpus` was omitted.

### Step 2: Phase 1 — Claim Definition

- Restate the hypothesis in one falsifiable sentence.
- Pin the grounding corpus and extraction rule (paths, how to isolate the relevant records).
- Clarify what would count as the claim being **false**.
- Write a `## Round 1` section into the state file.

### Step 3: Phase 2 — Deductive Derivation (Claude)

Following `references/prediction-template.md`, derive **3–5 falsifiable predictions**, each with 支持条件 / 反証条件 / Measure, including **at least one counter-test**. Append them under `### Deductive — Predictions` in the state file with the Edit tool.

### Step 4: Phase 3 — Inductive Verification

Fill `references/induction-verification-template.md` with the hypothesis, predictions, and corpus rule.

**Language directive** (both paths): read the project language and build the directive with the helper:

```bash
export CODEX_SKILL_CONTEXT=1

# Re-source helpers (each command bash block runs in its own shell — no shared state)
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

SETTINGS_FILE=".claude/codex-collab.local.md"
LANGUAGE="en"
if [ -f "$SETTINGS_FILE" ]; then
  # NOTE: use sed, NOT `awk '{print $2}'` — the literal `$2` inside a slash-command
  # bash block collides with positional-argument substitution and gets clobbered.
  LANGUAGE=$(sed -n 's/^language:[[:space:]]*\([A-Za-z][A-Za-z-]*\).*/\1/p' "$SETTINGS_FILE" 2>/dev/null)
  [ -z "$LANGUAGE" ] && LANGUAGE="en"
fi
LANG_DIRECTIVE=$(codex_get_language_directive "$LANGUAGE")  # empty for "en"
```

**If mode = codex** — delegate to Codex (independent verifier):

- **Round 1 (MCP path, primary):**
  ```
  mcp__codex__codex(
    prompt: "<filled induction-verification template>",
    developer-instructions: "<LANG_DIRECTIVE>",
    sandbox: "read-only",
    cwd: "<corpus root>"
  )
  ```
  Save the returned `threadId`.
- **Round 2+:** `mcp__codex__codex-reply(threadId, prompt)` with the updated hypothesis/predictions — the thread retains prior measurements.
- **Bash fallback:** write the filled template (with `$LANG_DIRECTIVE` prepended) to a prompt file, then call `codex_run_exec` with the **file path** as the first argument:
  ```bash
  export CODEX_SKILL_CONTEXT=1   # plus the Step 0 helper-loading block (own shell per block)
  PROMPT_FILE=$(codex_tmp_path "dialectic-loop-induction-prompt.txt")
  OUTPUT_FILE=$(codex_tmp_path "dialectic-loop-induction-output.md")
  # write the filled template into "$PROMPT_FILE" first (cat > "$PROMPT_FILE" <<EOF ... EOF)
  codex_run_exec "$PROMPT_FILE" "$OUTPUT_FILE" read-only
  ```
  Set Bash `timeout` to `min(wait_timeout + 60, 600) * 1000` ms. On MCP/exec failure, fall back to claude-only.

**If mode = claude-only** — Claude performs the empirical pass itself, but MUST script over the real corpus (re-read from disk, no cached content) and actively hunt counterexamples.

Append the verdicts and `### Inductive — Evidence` (per-prediction 【支持/部分支持/反証】 + numbers + quotes + 総合所見) to the state file.

### Step 5: Phase 4 — Arbitration (Claude)

- Build the **scorecard** (each Pi: predicted vs observed → 支持/部分支持/反証).
- Explicitly name every prediction where the deductive framing **over- or under-reached** (partial/falsified ones).
- Fold in the inductive role's missed-nuances.
- Write **H′** (updated hypothesis) and a **confidence** (low/medium/high) with reasoning.
- Append `### Arbitration` to the state file and increment `round`.

### Step 6: Phase 5 — Iterate or Conclude

- If **H′ changed materially** and `round < max_rounds` → return to **Step 3** with H′ as the new hypothesis (apply `--rotate` if set: swap deductive/inductive authorship).
- If **H′ converged** (≈ previous H) or `round >= max_rounds` → proceed to Step 7.

### Step 7: Phase 6 — Conclude and Report

Set `status: completed` and final `confidence` in the state file, then report to the user:

```markdown
## Dialectic Loop Complete

**Claim (H):**    <original>
**Refined (H′):** <hypothesis that survived the evidence>
**Confidence:**   <low/medium/high> (<why — independence, N, falsified predictions>)

### Prediction scorecard
- P1 <verdict> (<measure>) · P2 ... · P3 ... · P4 ...

### What the original framing missed
1. ...
2. ...

Loop log: tmp/dialectic-loop/<task-id>.md
```

## Error Handling

- **Codex unavailable in codex mode:** auto-fall back to claude-only; inform the user.
- **Inductive role returns no numbers:** treat the prediction as unverified; re-run with an explicit demand to compute the Measure over the corpus.
- **Corpus inaccessible:** stop and ask the user for a valid path rather than guessing.
- **Early stop requested:** report H′ so far with interim confidence and note the loop did not converge.

## Compact Recovery

1. `TaskList` for progress; read `tmp/dialectic-loop/<task-id>.md`.
2. Resume by which sections are filled (predictions → Phase 3; evidence → Phase 4; arbitration with changed H′ → next round; converged → report).

## Notes

- Loop state is persisted to survive compaction; each loop has a unique task id.
- The **inductive role must be grounded in the real corpus** (scripted, disk-read) — this is the skill's load-bearing constraint.
- The **arbiter is mandatory**: it exists to stop partial falsification from being glossed as partial support.
- Independence (Codex as inductive verifier ≠ hypothesis author) is the default and the point.
- All bash blocks use `awk` for safe text substitution.
