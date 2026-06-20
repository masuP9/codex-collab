---
name: dialectic-loop
description: Validate and refine an empirical claim by deriving predictions and testing them against a real corpus (deductive → inductive → arbiter loop)
argument-hint: [claim] [--corpus PATH/GLOB] [--mode codex|claude-only] [--max-rounds N] [--rotate] [--abduce]
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

1. **Parse options** from `$ARGUMENTS`: `--corpus <path|glob>`, `--mode <codex|claude-only>`, `--max-rounds <N>`, `--rotate`, `--abduce`. The remainder is the claim.
2. **Determine mode**: default `codex` when `command -v codex` succeeds, else `claude-only`; honor `--mode` override. Default `--max-rounds` is 3.
3. **`--abduce` (abduction variant) validation** — when `--abduce` is present:
   - It is the **only** trigger for the abduction variant; omitting the claim alone does **not** auto-enable it.
   - **`--corpus` is required** (Codex needs a corpus to abduce from). The claim is **optional** (Codex generates it).
   - **Requires `mode = codex`.** `--abduce --mode claude-only` is an **error** (abduction is delegated to Codex) — stop and tell the user.
   - **`--abduce --rotate` is an error** (the abduction variant fixes roles: Codex = abduction + induction, Claude = deduction + arbitration; rotation has no defined meaning) — stop and tell the user.
   - Set `variant: codex-abduction` (default otherwise is `variant: default`).
4. **Generate task id and state file** at `tmp/dialectic-loop/<task-id>.md`. Use the `dialectic-loop/v2` schema when `--abduce` is set, else `dialectic-loop/v1` (see SKILL.md → State File; v1 is read as `variant: default`). Use `awk` for safe substitution of the claim/corpus into the template. Confirm the corpus path with the user if `--corpus` was omitted (in default variant).
5. **Routing**: if `variant = codex-abduction` → proceed to **Step 1.5 (Phase 0: Abduction)**. Otherwise → **Step 2 (Phase 1)**.

### Step 1.5: Phase 0 — Abduction (Codex) — `--abduce` only

Run this step **only** when `variant = codex-abduction`. It has two sub-stages on a **dedicated abduction thread** (kept separate from the later induction thread).

**0a. Candidate generation (Codex).** Fill `references/abduction-template.md` and start a **new** Codex thread (this is the *abduction* thread):

```
mcp__codex__codex(
  prompt: "<filled abduction-template>",
  developer-instructions: "<LANG_DIRECTIVE>",   // derive as in Step 4
  sandbox: "read-only",
  cwd: "<corpus root>"
)
```

- Demand **multiple competing candidate hypotheses** (not one), each with the observations that suggest it, an alternative explanation, and a discriminating measure hint.
- **Persist the candidates first**: write Codex's full candidate list into a `## Abduction` → `### Candidates` section of the state file, save the returned `threadId` as **`abduction_thread_id`**, and **only then** set `abduction_status: done`. (Compact Recovery's "candidates present" check depends on this — do not mark done before the candidates are on disk.)
- **Bash fallback**: write the filled template to a prompt file and `codex_run_exec "$PROMPT_FILE" "$OUTPUT_FILE" read-only`.
- On Codex failure here, follow **Error Handling → `--abduce` failure** (do **not** silently fall back to claude-only).

**0b. Hypothesis selection (Claude / user).** Claude evaluates the candidates (falsifiability, discriminability, interest) and selects one — or presents them with `AskUserQuestion` for the user to choose / edit. Record the chosen hypothesis as `confirmed_hypothesis`, set `hypothesis_status: confirmed`, and `original_claim` (the user-supplied claim if any, else empty). This confirmed hypothesis becomes **H** for Phase 1+.

After 0b, continue to **Step 2** with H = `confirmed_hypothesis`.

### Step 2: Phase 1 — Claim Definition

- Restate the hypothesis in one falsifiable sentence (in the abduction variant, this is `confirmed_hypothesis` from Phase 0).
- Pin the grounding corpus and extraction rule (paths, how to isolate the relevant records).
- Clarify what would count as the claim being **false**.
- Write a `## Round 1` section into the state file; set `phase: deductive`.

### Step 3: Phase 2 — Deductive Derivation (Claude)

Following `references/prediction-template.md`, derive **3–5 falsifiable predictions**, each with 支持条件 / 反証条件 / Measure, including **at least one counter-test**. Append them under `### Deductive — Predictions` in the state file with the Edit tool.

### Step 4: Phase 3 — Inductive Verification

Set `phase: inductive` in the state file. Fill `references/induction-verification-template.md` with the hypothesis, predictions, and corpus rule.

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

- **Round 1 (MCP path, primary):** start a **fresh induction thread**.
  ```
  mcp__codex__codex(
    prompt: "<filled induction-verification template>",
    developer-instructions: "<LANG_DIRECTIVE>",
    sandbox: "read-only",
    cwd: "<corpus root>"
  )
  ```
  Save the returned `threadId` as **`induction_thread_id`**.
  - **Abduction variant (`--abduce`) — load-bearing:** the induction thread **must be different from `abduction_thread_id`**. Pass **only** the confirmed H, Claude's predictions, and the corpus rule — **never** the abduction thread's candidates, rationale, or confidence. This prevents the verifier from being anchored to the hypothesis's own generation context (same model, but no context contamination).
- **Round 2+:** `mcp__codex__codex-reply(induction_thread_id, prompt)` with the updated hypothesis/predictions — the induction thread retains prior measurements. (Never continue on the abduction thread.)
- **Bash fallback:** write the filled template (with `$LANG_DIRECTIVE` prepended) to a prompt file, then call `codex_run_exec` with the **file path** as the first argument:
  ```bash
  export CODEX_SKILL_CONTEXT=1   # plus the Step 0 helper-loading block (own shell per block)
  PROMPT_FILE=$(codex_tmp_path "dialectic-loop-induction-prompt.txt")
  OUTPUT_FILE=$(codex_tmp_path "dialectic-loop-induction-output.md")
  # write the filled template into "$PROMPT_FILE" first (cat > "$PROMPT_FILE" <<EOF ... EOF)
  codex_run_exec "$PROMPT_FILE" "$OUTPUT_FILE" read-only
  ```
  Set Bash `timeout` to `min(wait_timeout + 60, 600) * 1000` ms. On MCP/exec failure: in the **default variant**, fall back to claude-only; in the **`--abduce` variant**, do **not** fall back — follow Error Handling → `--abduce` failure (retry, then stop / ask the user).
  - **Bash mode (no threadId):** `codex exec` is stateless and returns no thread id. Thread "separation" is then automatic (each call is a fresh process). To keep the "IDs must differ" invariant true, record distinct sentinels: `abduction_thread_id: bash-exec-abduction` and `induction_thread_id: bash-exec-induction`. The isolation guard still holds: the induction prompt must contain only H + predictions + corpus rule, never the abduction prompt/candidates.

**If mode = claude-only** — Claude performs the empirical pass itself, but MUST script over the real corpus (re-read from disk, no cached content) and actively hunt counterexamples.

Append the verdicts and `### Inductive — Evidence` (per-prediction 【支持/部分支持/反証】 + numbers + quotes + 総合所見) to the state file.

### Step 5: Phase 4 — Arbitration (Claude)

- Build the **scorecard** (each Pi: predicted vs observed → 支持/部分支持/反証).
- Explicitly name every prediction where the deductive framing **over- or under-reached** (partial/falsified ones).
- Fold in the inductive role's missed-nuances.
- **Second independent verification (mandatory in the `--abduce` variant; recommended always):** Claude **re-reads the corpus from disk** and **recomputes each Measure** that drives a verdict — by default **in full**. If full recomputation is infeasible, sample and record in the state file: the sampling method, the count, the selection/seed rule, the tolerance, and the mismatch criterion (a rate verified only by a few cherry-picked examples does **not** count). Record any Codex-vs-disk discrepancy and fold it into the confidence.
- **Evidence scope (abduction variant):** when the hypothesis was **abduced from the same corpus** it is now tested on, this is in-sample fit (discovery = validation data). Set `evidence_scope: exploratory_in_sample`, keep `confidence` modest, and note in the report that **confirmatory strength requires a holdout / fresh corpus**. When discovery and validation corpora differ, use `evidence_scope: confirmatory`.
- Write **H′** (updated hypothesis), a **confidence** (low/medium/high), and `evidence_scope` with reasoning.
- Append `### Arbitration` to the state file, set `phase: arbitration`, and increment `round`.

### Step 6: Phase 5 — Iterate or Conclude

- If **H′ changed materially** and `round < max_rounds` → return to **Step 3** with H′ as the new hypothesis (apply `--rotate` if set: swap deductive/inductive authorship).
- If **H′ converged** (≈ previous H) or `round >= max_rounds` → proceed to Step 7.

### Step 7: Phase 6 — Conclude and Report

Set `phase: report`, `status: completed`, and final `confidence` (and `evidence_scope` in the abduction variant) in the state file, then report to the user:

```markdown
## Dialectic Loop Complete

**Claim (H):**    <original — for --abduce, note "abduced by Codex" + original_claim if any>
**Refined (H′):** <hypothesis that survived the evidence>
**Confidence:**   <low/medium/high> (<why — independence, N, falsified predictions>)
**Evidence:**     <confirmatory | exploratory_in_sample> (<for in-sample: recommend holdout/fresh corpus to confirm>)

### Prediction scorecard
- P1 <verdict> (<measure>) · P2 ... · P3 ... · P4 ...

### What the original framing missed
1. ...
2. ...

Loop log: tmp/dialectic-loop/<task-id>.md
```

## Error Handling

- **Codex unavailable in codex mode (default variant):** auto-fall back to claude-only; inform the user.
- **`--abduce` failure (Codex unavailable / abduction or induction call fails):** do **NOT** silently fall back to claude-only — having Claude generate or test the hypothesis breaks the author≠verifier contract. Instead: stop and retry once; if it still fails, ask the user whether to (a) abort, or (b) switch to the **default variant** with an explicit user-supplied claim (claim then required).
- **Inductive role returns no numbers:** treat the prediction as unverified; re-run with an explicit demand to compute the Measure over the corpus.
- **Corpus inaccessible:** stop and ask the user for a valid path rather than guessing.
- **Early stop requested:** report H′ so far with interim confidence and note the loop did not converge.

## Compact Recovery

1. `TaskList` for progress; read `tmp/dialectic-loop/<task-id>.md`; read `phase` / `*_status` / thread-id fields from the frontmatter.
2. Resume by `phase` (and, for `--abduce`, by `abduction_status` / `hypothesis_status`):

| State | Resume at |
|-------|-----------|
| `variant: codex-abduction`, no candidates / `abduction_status` ≠ done | Phase 0a (regenerate candidates on a new abduction thread) |
| candidates present, `hypothesis_status` ≠ confirmed | Phase 0b (selection) |
| H confirmed, no predictions | Phase 2 (deductive) |
| predictions present, no evidence | Phase 3 (inductive) |
| evidence present, no arbitration | Phase 4 (arbitration) |
| arbitration present, H′ changed, rounds remain | Phase 2 (next round) |
| H′ converged or max_rounds reached | Phase 6 (report) |

3. **Thread recovery (per phase, abduction variant):** if `abduction_thread_id` is lost but candidates are already recorded, do **not** regenerate the abduction thread. If `induction_thread_id` is lost mid-loop, start a **fresh induction thread** from the current round's confirmed H + Claude's predictions + corpus rule and **recompute that round** (never reuse the abduction thread).

## Notes

- Loop state is persisted to survive compaction; each loop has a unique task id.
- The **inductive role must be grounded in the real corpus** (scripted, disk-read) — this is the skill's load-bearing constraint.
- The **arbiter is mandatory**: it exists to stop partial falsification from being glossed as partial support.
- Independence (inductive verifier ≠ hypothesis author) is the default and the point. In the **abduction variant** Codex authors *and* tests, so independence is preserved structurally instead: predictions are Claude's, arbitration is Claude's (with mandatory disk recompute), and the induction thread is isolated from the abduction thread.
- All bash blocks use `awk`/`sed` for safe text substitution (use `sed`, not `awk '{print $2}'`, inside command bash blocks — `$2` collides with slash-command positional substitution).
