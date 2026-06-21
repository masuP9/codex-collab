---
name: contradiction-lift
description: Have Claude and Codex solve the same question independently, then lift the divergence to a higher frame (Aufhebung) — a selection mechanism or an honest aporia, never an average
argument-hint: [question] [--mode codex|claude-only] [--max-lift-attempts N]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, AskUserQuestion, mcp__codex__codex, mcp__codex__codex-reply
---

# Contradiction Lift

Solve a question with Claude and Codex **independently**, raise the contradiction from where they diverge, and pursue **Aufhebung (止揚)** — preserve both truth-moments and lift to a higher frame. Output is a **selection mechanism** or an **honest aporia**, never an average. See `skills/contradiction-lift/SKILL.md` for the full methodology.

## Question

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

1. **Parse options** from `$ARGUMENTS`: `--mode <codex|claude-only>`, `--max-lift-attempts <N>` (default 2). The remainder is the question `Q`.
2. **Determine mode**: default `codex` when `command -v codex` succeeds, else `claude-only`; honor `--mode` override. In `claude-only`, **warn** that independence is weak (the core is two *different* models diverging) and recommend `codex`.
3. **Scope check**: this skill is for questions where multiple reasonable decision rules remain and a single experiment can't settle the whole. If the question is a plain bug / perf comparison / spec-conformance, suggest `strong-inference`; if it's stress-testing one proposal, suggest `devils-advocate`; if it's a claim-vs-data check, suggest `dialectic-loop`.
4. **Generate task id and state file** at `tmp/contradiction-lift/<task-id>.md` using the `contradiction-lift/v1` schema (see SKILL.md → State File). Use `awk` for safe substitution of the question into the template. Set `state: contract`.

**Language directive** (used for every Codex delegation below):

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

### Step 2: Phase 0 — Decision Contract

Fix the shared frame and write it to `## Decision Contract` in the state file: the question `Q`, success conditions, constraints, immovable requirements, empirically observable variables, and the required decision format. Confirm with the user (a vague contract makes an interpretation gap look like a contradiction). Keep `state: contract`.

### Step 3: Phase 1 — Sealed Solutions (independent, do NOT cross-contaminate)

Both solvers answer `Q` against the same contract, **sealed** (neither sees the other). Each uses `references/sealed-solution-template.md` and submits the **decision function**, load-bearing assumptions, invariants, rejected alternatives, the flip observation, and confidence.

- **Solver A = Claude (native):** produce Solution A and write it under `### Solution A (Claude)`.
- **Solver B = Codex (fresh thread, read-only):**
  ```
  mcp__codex__codex(
    prompt: "<Decision Contract + sealed-solution-template>",   // NEVER include Solution A
    developer-instructions: "<LANG_DIRECTIVE>",
    sandbox: "read-only",
    cwd: "<project root>"
  )
  ```
  Save the threadId as `solver_b_thread_id`; write the result under `### Solution B (Codex)`.
- **Bash fallback:** write the prompt to a file and `codex_run_exec "$PROMPT_FILE" "$OUTPUT_FILE" read-only`; set `solver_b_thread_id: bash-exec-solver`.
- **Sealing guard:** never put Solution A into Solver B's prompt before both are sealed.

Set `state: sealed`.

### Step 4: Phase 2 — Divergence Mapping (anonymized)

Anonymize the two solutions as **X / Y** and delegate mapping to a **fresh** Codex thread (a different role from Solver B) using `references/divergence-map-template.md`:

```
mcp__codex__codex(
  prompt: "<contract + Solution X + Solution Y, anonymized; build the typed disagreement ledger with flip-test>",
  developer-instructions: "<LANG_DIRECTIVE>",
  sandbox: "read-only",
  cwd: "<project root>"
)
```

- Save `mapper_thread_id` (Bash: `bash-exec-mapper`).
- Type each disagreement (`semantic|empirical|causal|normative|constraint|uncertainty`) and mark **load-bearing** ones via the **flip-test** (flip only that premise — does the conclusion/decision rule change?).
- Append `## Divergence Ledger`; set `state: mapped`.
- **No material divergence:** if the ledger has **no load-bearing disagreement**, set `state: no_material_divergence` and `outcome: no_material_divergence` (no lift attempted), and report that both solutions share the load-bearing core. **Do not fabricate a contradiction** — skip to Step 9 with this outcome.

### Step 5: Phase 3 — Adjudication Router

Route each disagreement and append `## Adjudication`:
- **empirical/observable** → **pre-register** "if result X → A, if Y → B" in the state file **first**, then have Codex run a **discriminating** experiment (default `sandbox: read-only`; `workspace-write` only if the experiment must build/run, with user confirmation). Set `empirical_arbiter: done` when finished.
- **semantic** → normalize the term, dissolve the disagreement.
- **constraint** → check against the Decision Contract.
- **normative / unobservable-causal** → carry forward to Preservation.

If there are **no empirical disagreements** to run, set `empirical_arbiter: not_applicable` (not `pending`). Set `state: adjudicated`.

### Step 6: Phase 4 — Preservation Contract (mutual steelman, accept/repair-once)

For the disagreements that remain, each party steelmans the **other**: conditions under which the other is strongest, the truth-moment lost if discarded, a concrete failure without it, and the incompatible core that remains. The other reviews with **`accept` / `repair once`** only (review = "is my reasoning faithfully represented?", not "do I agree?"). Use `codex-reply` on `solver_b_thread_id` for Codex's steelman/review. Append `## Preservation`; set `state: preserved`.

- **If a steelman is still not accepted after the single repair:** do **not** silently proceed. Record the contested truth-moment as **uncertified** in `## Preservation`. An uncertified load-bearing moment cannot be conserved, so it will fail the Audit's **Conservation** test → the run resolves to `aporia` (the parties cannot even agree on what the other is preserving). Carry the uncertified moment forward so the audit sees it.

### Step 7: Phase 5 — Lift Construction (anonymized, fresh thread)

Delegate to a **fresh** "Lift Architect" thread (anonymized inputs) using `references/lift-audit-template.md`. Build a **selection mechanism** `f(C) → A | B | N`, not a position. Required: conserved moments of both; any **new** variable/relation; an example selecting A, one selecting B, and **one differing from a simple average**; failure conditions. `Q'` is optional (a threshold/ordering/option-value/reversibility-staged decision also counts). Save `lift_thread_id`; append `## Lift`; increment `lift_attempts`; set `state: lifted`.

### Step 8: Phase 6 — Lift Audit (independent thread)

Delegate the audit to an **independent** thread that did **not** build the lift (`audit_thread_id ≠ lift_thread_id`). Run all **7 tests** (Conservation, Discrimination, Novelty, Non-vacuity, Dominance, Falsifiability, Feasibility) and demand the **causal mechanism** ("why does that condition change the choice?"). Append `## Audit`.

- **All 7 pass AND the causal mechanism is stated (causal check = yes)** → `outcome: lifted`, `state: accepted` → Step 9. (A 7/7 with `causal check = no` does **not** pass — a mechanism-less router is not a lift.)
- **Any fail** and `lift_attempts < max_lift_attempts` → return to **Step 7** (reconstruct once).
- **Any fail** and `lift_attempts >= max_lift_attempts` → `outcome: aporia`, `state: aporia` → Step 9.

### Step 9: Conclude and Report

Report using the **Output Format** in SKILL.md — the **Accepted lift** block (mechanism, conserved moments, A/B/average-differ examples, falsifier, 7/7 + causal=yes), the **Honest aporia** block (irreducible axis, A-right-when / B-right-when, which test failed twice), or, when `state: no_material_divergence`, a short note that both solutions share the load-bearing core (no lift needed). Point to `tmp/contradiction-lift/<task-id>.md`.

## Error Handling

- **Codex unavailable in codex mode:** auto-fall back to `claude-only`; **warn** that independence is weak (two passes by the same model).
- **Solver B / a fresh-thread role fails:** retry once; if it still fails, fall back to claude-only for that role with an explicit independence caveat.
- **Lift keeps failing audit:** after `max_lift_attempts`, declare an **honest aporia** (do not manufacture a synthesis — that disguises an average).
- **Early stop requested:** report the current `state` (sealed solutions / ledger / lift so far) and note no lift was reached.

## Compact Recovery

1. `TaskList` for progress; read `tmp/contradiction-lift/<task-id>.md`; read `state` / `*_thread_id` / `lift_attempts`.
2. Resume by `state`: `contract`→Phase 0/1, `sealed`→Phase 2, `mapped`→Phase 3, `adjudicated`→Phase 4, `preserved`→Phase 5, `lifted`→Phase 6, `accepted`/`aporia`/`no_material_divergence`→report.
3. **Thread recovery:** a lost fresh-thread role is restarted from its persisted inputs (ledger / sealed solutions / lift on disk). Keep `audit_thread_id ≠ lift_thread_id`.

## Notes

- Loop state is persisted to survive compaction; each run has a unique task id.
- **Sealing is load-bearing**: solve independently, reveal afterward (showing the other first collapses the divergence).
- **The third-party roles are approximated** (only two models): fresh threads + anonymized inputs + no reasoning history — state this honestly, don't overclaim independence.
- **Never optimize for agreement / average / residual-shrink.** A diluted middle ground is failure; an honest aporia beats a fake third term.
- All bash blocks use `awk`/`sed` for safe text substitution (use `sed`, not `awk '{print $2}'`, inside command bash blocks — `$2` collides with slash-command positional substitution).
