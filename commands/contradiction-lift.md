---
name: contradiction-lift
description: Have Claude and Codex solve the same question independently, then lift the divergence to a higher frame (Aufhebung) — a selection mechanism or an honest aporia, never an average
argument-hint: [question] [--mode codex|claude-only] [--max-lift-attempts N]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Task, AskUserQuestion, mcp__codex__codex, mcp__codex__codex-reply
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
4. **Generate task id and state file** at `tmp/contradiction-lift/<task-id>.md` using the `contradiction-lift/v2` schema (see SKILL.md → State File). Use `awk` for safe substitution of the question into the template. Set `state: contract`.

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

### Step 3: Phase 1 — Sealed Solutions (independent, parallel, do NOT cross-contaminate)

Both solvers answer `Q` against the same contract, **sealed** (neither sees the other). Each uses `references/sealed-solution-template.md` and submits the **decision function**, load-bearing assumptions, invariants, rejected alternatives, the flip observation, and confidence.

**Dispatch Solver A and Solver B in parallel (same message), then read both.** The orchestrator must **not** author Solution A itself — by the time it has dispatched Solver B it is contaminated. Solver A runs in a **fresh Claude subagent** with its own context.

- **Solver A = fresh Claude subagent (Task tool):**
  ```
  Task(
    subagent_type: "general-purpose",   // prefer a read-only type (e.g. "Explore") where available
    description: "Sealed Solver A",
    prompt: "<Decision Contract + sealed-solution-template>. Solve independently and return ONLY the filled template as your final message. Analysis only: do NOT edit/write/commit any files, and do not reference any other solution."
  )
  ```
  Write the returned result under `### Solution A (Claude)` (the **orchestrator** writes the state file, not the subagent). Keep `solver_a_role: claude-subagent`.
- **Solver B (sealed) — by `mode`:**
  - `mode: codex` → **Codex** (fresh thread, read-only):
    ```
    mcp__codex__codex(
      prompt: "<Decision Contract + sealed-solution-template>",   // NEVER include Solution A
      developer-instructions: "<LANG_DIRECTIVE>",
      sandbox: "read-only",
      cwd: "<project root>"
    )
    ```
    Save the threadId as `solver_b_thread_id`; write the result under `### Solution B (Codex)`.
    Bash fallback: write the prompt to a file and `codex_run_exec "$PROMPT_FILE" "$OUTPUT_FILE" read-only`; set `solver_b_thread_id: bash-exec-solver`.
  - `mode: claude-only` → a **second fresh Claude subagent** (Task, analysis-only — same prompt constraints as Solver A), set `solver_b_thread_id: claude-subagent-solverB`; write under `### Solution B (Claude #2)`. Warn that independence is context-only (same prior).
- **Sealing guards:** dispatch both before reading either; never put Solution A into Solver B's prompt (or vice versa) before both are sealed; the orchestrator authors neither.
- **Fallbacks (degraded):**
  - **No Task tool** (subagents unavailable): the orchestrator authors Solution A **first**, while still blind to Solver B, and **persists it to the state file** — **set `solver_a_role: orchestrator-fallback`** — and only **then** dispatches Solver B (whose response will enter the orchestrator's context, which is now safe because A is already sealed). Authoring A *after* seeing B is forbidden. Note in the report that sealing was disciplinary, not structural.
  - **No Codex *and* no Task tool**: Solver B cannot be produced cross-context → **stop** and report that the run is not feasible (a single same-context author is neither sealed nor independent). Do not fabricate a second solution.

Set `state: sealed`.

### Step 4: Phase 2 — Divergence Mapping (anonymized)

Anonymize the two solutions as **X / Y** and delegate mapping to a **fresh** role (a different role from Solver B) using `references/divergence-map-template.md`. The mapper may be a **fresh Claude subagent** (`Task`, set `mapper_role: claude-subagent`) or a **fresh Codex thread** (set `mapper_role: codex-thread`):

```
# Codex-thread option:
mcp__codex__codex(
  prompt: "<contract + Solution X + Solution Y, anonymized; build the typed disagreement ledger with flip-test>",
  developer-instructions: "<LANG_DIRECTIVE>",
  sandbox: "read-only",
  cwd: "<project root>"
)
# Subagent option:
Task(subagent_type: "general-purpose", description: "Divergence Mapper",
     prompt: "<contract + anonymized X/Y; build the typed disagreement ledger with flip-test>. Analysis only: do NOT edit/write/commit files; return the ledger as your final message.")
```

> **All Task-dispatched roles** (Solver A, Solver B in claude-only, Mapper, Lift Architect, Meta Auditor, and the Phase 4 party re-seed) carry the **same analysis-only constraint** — no file writes; the orchestrator records their returned artifact into the state file.

- Save the mapper **actor key** in `mapper_thread_id`: Codex `threadId` (MCP) / `bash-exec-mapper` (Bash) / `claude-subagent-mapper` (subagent).
- Type each disagreement (`semantic|empirical|causal|normative|constraint|uncertainty`) and mark **load-bearing** ones via the **flip-test** (flip only that premise — does the conclusion/decision rule change?).
- Append `## Divergence Ledger`; set `state: mapped`.
- **No material divergence:** if the ledger has **no load-bearing disagreement**, set `state: no_material_divergence` and `outcome: no_material_divergence` (no lift attempted), and report that both solutions share the load-bearing core. **Do not fabricate a contradiction** — skip to Step 9 with this outcome.

### Step 5: Phase 3 — Adjudication Router

Route each disagreement and append `## Adjudication`:
- **empirical/observable** → **pre-register** "if result X → A, if Y → B" in the state file **first**, then have Codex run a **discriminating** experiment (default `sandbox: read-only`; `workspace-write` only if the experiment must build/run, with user confirmation). Set `empirical_arbiter: done` when finished.
- **semantic** → normalize the term, dissolve the disagreement.
- **constraint** → check against the Decision Contract.
- **normative / unobservable-causal** → carry forward to Preservation.

If there are **no empirical disagreements** to run, set `empirical_arbiter: not_applicable` (not `pending`). If an empirical disagreement **exists but its discriminating experiment cannot be run this session** (e.g., no benchmark/corpus available), still **pre-register** the experiment ("if X → A, if Y → B"), set `empirical_arbiter: deferred`, and carry the residual to the lift **conditionally on that observable** (do not guess the result). Set `state: adjudicated`.

### Step 6: Phase 4 — Preservation Contract (mutual steelman, accept/repair-once)

For the disagreements that remain, each party steelmans the **other**: conditions under which the other is strongest, the truth-moment lost if discarded, a concrete failure without it, and the incompatible core that remains. The other reviews with **`accept` / `repair once`** only (review = "is my reasoning faithfully represented?", not "do I agree?").

**The orchestrator mediates a 4-substep handshake** (no single role can do it alone — each step's output is the next step's input):

1. **Steelman (both sides, parallel).** Each party steelmans the **other**, seeded with Solution A + Solution B:
   - Claude side → fresh subagent (analysis-only): `Task(... "Steelman the OTHER side (Y). Output only the steelman.")` → "A-steelmans-B".
   - Codex side (`mode: codex`) → `codex-reply(solver_b_thread_id, "Steelman the OTHER side …")` → "B-steelmans-A".
2. **Cross-review (accept / repair-once).** The orchestrator hands each steelman to the party it is *about*:
   - "A-steelmans-B" → to **B** (`codex-reply`): "Is your reasoning represented faithfully? Reply `accept` or `repair once`."
   - "B-steelmans-A" → to a **fresh Claude subagent** seeded with Solution A + the steelman: same accept / repair-once prompt.
3. **Repair once (if requested).** The orchestrator returns the repair request to the **original steelman author** (the other party) for **one** revision, then re-reviews once.
4. **Record.** `accept` → the truth-moment is conserved; **still not accepted after the one repair → mark it `uncertified`** in `## Preservation` (it will fail the Audit's Conservation test → `aporia`).

**By mode / fallback:**
- `mode: claude-only` → every Codex step above becomes a fresh re-seeded Claude subagent (`claude-subagent-preserveB` for the B side); warn that reviews are same-prior.
- **No Task tool** → the re-seed is impossible, so the orchestrator performs the **Claude-side** steelman and review itself (degraded — this is the documented Phase-4 exception; note it in the report); the Codex side still uses `codex-reply` when available.

Append `## Preservation`; set `state: preserved`.

- **If a steelman is still not accepted after the single repair:** do **not** silently proceed. Record the contested truth-moment as **uncertified** in `## Preservation`. An uncertified load-bearing moment cannot be conserved, so it will fail the Audit's **Conservation** test → the run resolves to `aporia` (the parties cannot even agree on what the other is preserving). Carry the uncertified moment forward so the audit sees it.

### Step 7: Phase 5 — Lift Construction (anonymized, fresh thread)

Delegate to a **fresh** "Lift Architect" role (anonymized inputs) — a Claude subagent (`Task`, set `lift_role: claude-subagent`) or a Codex thread (set `lift_role: codex-thread`) — using `references/lift-audit-template.md`. Build a **selection mechanism** `f(C) → A | B | N`, not a position. Required: conserved moments of both; any **new** variable/relation; an example selecting A, one selecting B, and **one differing from a simple average**; failure conditions. `Q'` is optional (a threshold/ordering/option-value/reversibility-staged decision also counts). Save `lift_role` and the `lift_thread_id` **actor key** (Codex `threadId` / `bash-exec-lift` / `claude-subagent-lift`); append `## Lift`; increment `lift_attempts`; set `state: lifted`.

### Step 8: Phase 6 — Lift Audit (independent thread)

Delegate the audit to an **independent** role that did **not** build the lift. **Prefer cross-model pairing**: if `lift_role: claude-subagent`, run the audit on **Codex** (set `audit_role: codex-thread`); if `lift_role: codex-thread`, run the audit on a **Claude subagent** (set `audit_role: claude-subagent`) — so a correlated blind spot is **far less likely** to pass both build and audit. Save the `audit_thread_id` **actor key** (Codex `threadId` / `bash-exec-audit` / `claude-subagent-audit`) and keep `audit_thread_id ≠ lift_thread_id` — the per-role sentinels **record** this distinctness even when both roles are Claude subagents (`claude-subagent-audit ≠ claude-subagent-lift`); it is a procedural record, not a runtime proof, so always dispatch a **new** subagent per role. Run all **7 tests** (Conservation, Discrimination, Novelty, Non-vacuity, Dominance, Falsifiability, Feasibility) and demand the **causal mechanism** ("why does that condition change the choice?"). Append `## Audit`.

- **All 7 pass AND the causal mechanism is stated (causal check = yes)** → `outcome: lifted`, `state: accepted` → Step 9. (A 7/7 with `causal check = no` does **not** pass — a mechanism-less router is not a lift.)
- **Any fail** and `lift_attempts < max_lift_attempts` → return to **Step 7** (reconstruct once).
- **Any fail** and `lift_attempts >= max_lift_attempts` → `outcome: aporia`, `state: aporia` → Step 9.

### Step 9: Conclude and Report

Report using the **Output Format** in SKILL.md — the **Accepted lift** block (mechanism, conserved moments, A/B/average-differ examples, falsifier, 7/7 + causal=yes), the **Honest aporia** block (irreducible axis, A-right-when / B-right-when, which test failed twice), or, when `state: no_material_divergence`, a short note that both solutions share the load-bearing core (no lift needed). Point to `tmp/contradiction-lift/<task-id>.md`.

## Error Handling

- **Codex unavailable in codex mode:** auto-fall back to `claude-only`; **warn** that independence is weak (two passes by the same model).
- **Solver B / a fresh-thread role fails:** retry once; if it still fails, **and the Task tool is available**, fall back to a fresh Claude subagent for that role with an explicit independence caveat (same-prior); **if the Task tool is unavailable too**, do not silently degrade — **stop**, leave `state` at its last valid value (do not invent a new state), and report the **run** as incomplete (no cross-context role could be produced).
- **Lift keeps failing audit:** after `max_lift_attempts`, declare an **honest aporia** (do not manufacture a synthesis — that disguises an average).
- **Early stop requested:** report the current `state` (sealed solutions / ledger / lift so far) and note no lift was reached.

## Compact Recovery

1. `TaskList` for progress; read `tmp/contradiction-lift/<task-id>.md`; read `state` / `*_thread_id` / `lift_attempts`.
2. Resume by `state`: `contract`→Phase 0/1, `sealed`→Phase 2, `mapped`→Phase 3, `adjudicated`→Phase 4, `preserved`→Phase 5, `lifted`→Phase 6, `accepted`/`aporia`/`no_material_divergence`→report.
3. **Role recovery:** every independence-bearing role is stateless — restart it from persisted inputs (ledger / sealed solutions / lift on disk). Codex roles resume by thread or re-run; Claude-subagent roles (incl. Solver A's Phase-4 party actions) are re-dispatched as fresh subagents re-seeded from disk (no thread to resume — by design). Keep `audit_thread_id ≠ lift_thread_id`. A `v1` state file (no `*_role` fields): a **non-empty** `*_thread_id` ⇒ `*_role = codex-thread`; an **empty** `*_thread_id` ⇒ that phase had not run (leave empty, assign by the current rules on resume — do **not** infer `claude-subagent`); `solver_a_role = orchestrator-fallback`. Re-stamp `v2` on next write.

## Notes

- Loop state is persisted to survive compaction; each run has a unique task id.
- **Sealing is structural**: Solver A is a fresh Claude subagent (not the orchestrator), dispatched in parallel with Solver B; the orchestrator authors neither and reads neither until both return.
- **Two kinds of independence** (see SKILL.md → "Independence: two kinds"): a Claude subagent gives **context-independence** (fresh window, no history) but **not prior-independence**. Keep **solvers cross-model** (Claude subagent × Codex), and **pair verification across models** (Claude-built lift → Codex audit, and vice versa). A same-model agreement is not confirmation.
- **The orchestrator is dispatch-only** — it never authors a solution, steelman, lift, or audit (one documented exception: the Task-tool-unavailable fallback, where **Solver A and its Phase 4 party actions** revert to the orchestrator and sealing/context-separation degrade — flag both in the report).
- **Actor keys**: subagent roles record a `claude-subagent-<role>` sentinel in their `*_thread_id` so the `audit ≠ lift` distinctness check holds across MCP / Bash / subagent backends (a procedural record, not a runtime proof — freshness comes from always dispatching a new subagent). `claude-only` mode and the no-Task fallback cannot be cross-model — say so and distrust same-model agreement.
- **Never optimize for agreement / average / residual-shrink.** A diluted middle ground is failure; an honest aporia beats a fake third term.
- All bash blocks use `awk`/`sed` for safe text substitution (use `sed`, not `awk '{print $2}'`, inside command bash blocks — `$2` collides with slash-command positional substitution).
