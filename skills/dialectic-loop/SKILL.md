---
name: Dialectic Loop
description: 'This skill should be used when the user wants to "test a claim against data", "validate an empirical hypothesis", "refine a model/theory with evidence", "characterize a pattern and verify it", "演繹と帰納で検証", "仮説をデータで検証して更新", "実例と反例で確かめる", "弁証法ループ", "主張を現物で裏取り", "傾向分析を検証して精緻化", or mentions iteratively updating a hypothesis by deriving predictions and testing them against a real corpus. NOTE: Use this for VALIDATING/REFINING an empirical claim or model against real data through a derive→test→update loop. Use strong-inference for debugging an UNKNOWN cause, and devils-advocate for adversarially stress-testing a DESIGN proposal.'
---

# Dialectic Loop Skill

Validate and refine an empirical claim or model by running C.S. Peirce's inquiry cycle — **abduction → deduction → induction** — across three roles that debate and update a hypothesis against real data.

## Overview

A Dialectic Loop improves the quality of a *claim about reality* (a trend, a pattern, a characterization, an empirical model) by:

1. **Deriving** falsifiable predictions from a hypothesis (deductive role)
2. **Testing** those predictions against a real corpus — surfacing supporting instances **and actively hunting counterexamples** (inductive role)
3. **Arbitrating** the gap between prediction and evidence, then **updating** the hypothesis (arbiter role)
4. **Iterating** until the hypothesis stabilizes (converges)

The output is not approve/reject and not a root cause — it is a **refined hypothesis (H′) with an evidence-backed confidence level and a record of what the original framing got wrong.**

**Key feature**: In codex mode, the **inductive role is assigned to Codex** so the empirical test is performed by a *different model than the one that authored the hypothesis*. This independence is the point — it is what catches the hypothesis author's confirmation bias.

## Comparison with sibling skills

| Aspect | Strong Inference | Devil's Advocate | **Dialectic Loop** |
|--------|------------------|------------------|--------------------|
| Purpose | Find an unknown cause | Stress-test a design proposal | **Validate/refine an empirical claim or model** |
| Method | Competing hypotheses + eliminating experiments | Blue vs Red adversarial debate | **Derive predictions → test on real data → update** |
| Engine of truth | Decisive experiment | Adversarial critique | **Counterexample hunting on a real corpus** |
| Output | Root cause + evidence trail | Verdict (APPROVE/CONDITIONAL/REJECT) | **Refined hypothesis H′ + confidence + "what was missed"** |
| Loop ends when | One hypothesis survives | Max rounds / verdict | **Hypothesis converges (stops changing)** |
| Best for | Debugging | Design review | Trend analysis, profiling, theory refinement, claim-checking |

## Prerequisites

- The user has a **claim, hypothesis, or model** to validate (e.g. "X tends to do Y", "this pattern holds", "the system behaves like Z").
- A **corpus / data source** that can ground the test exists and is accessible (codebase, logs, dataset, documents).
- For Codex collaboration mode: Codex CLI available (`codex exec` / MCP `mcp__codex__codex`).

## Design principles (lessons baked in)

These are non-negotiable; they are what make the loop work rather than perform theater:

1. **Ground the inductive role in current artifacts.** The inductive verifier MUST re-read data from disk (ignore cached content), and MUST process large data with scripts/grep rather than eyeballing. A prediction "tested" without touching the corpus is invalid.
2. **Name roles by function, not persona.** The inductive role's job is *measurement + counterexample hunting*, not "acting inductive." The deductive role's job is *deriving falsifiable consequences*, not "being logical."
3. **The arbiter is mandatory.** Without a third role, a partially-falsified prediction gets quietly recorded as "partial support." The arbiter exists to force the question: *where did the hypothesis over- or under-reach?*
4. **Independence beats agreement.** Assign the inductive test to a different model than the hypothesis author. A confirming result from the same author is weak; a counterexample from an independent verifier is strong.
5. **Converge, don't exhaust.** Stop when H′ stops changing materially, not at a fixed round count.
6. **In the `--abduce` variant, preserve independence structurally (Codex authors *and* tests).** Four guards make this honest: (a) **Predictions are Claude's** — the believer does not design the test. (b) **Arbitration is Claude's, with a mandatory disk recompute** — the believer does not grade the result; the arbiter re-measures from disk (full, or sampled with recorded method/tolerance). (c) **Thread isolation** — induction runs on a *fresh* thread that receives only the confirmed H, Claude's predictions, and the corpus rule, never the abduction thread's candidates/rationale (no context contamination). (d) **In-sample honesty** — if H is abduced from the same corpus it is tested on, that is discovery=validation fit; mark `evidence_scope: exploratory_in_sample` and recommend a holdout/fresh corpus for confirmatory strength.

## Workflow Phases

### Phase 0: Abduction (Codex) — `--abduce` variant only

Skipped in the default variant (the user/Claude supplies the hypothesis). When `--abduce` is set, Codex generates the hypothesis from the corpus, in two sub-stages on a **dedicated abduction thread**:

1. **Candidate generation** — Codex re-reads the corpus from disk and proposes **multiple competing candidate hypotheses**, each with the observations that suggest it, an alternative explanation, and a discriminating measure hint. (A single hypothesis is rejected — it invites premature fixation.)
2. **Selection** — Claude (or the user, via a prompt) picks one candidate as the confirmed hypothesis **H**, which feeds Phase 1+.

The abduction thread is kept **separate** from the later induction thread (see Design principle #6).

### Phase 1: Claim Definition

When the user presents a claim:

1. **State the hypothesis crisply** — one sentence that could be wrong.
2. **Identify the grounding corpus** — exactly which files / logs / dataset will be the evidence base, and how to access them (paths, extraction rules).
3. **Clarify scope** — what is in and out of scope; what would count as the claim being *false*.

### Phase 2: Deductive Derivation (Deductive role — Claude)

Take the hypothesis **as given** and derive **3–5 falsifiable predictions**. Each prediction must specify:

- **What should be observed** in the corpus if the hypothesis is true.
- **支持条件 (support condition)** — the measurable result that confirms it.
- **反証条件 (falsifier)** — the measurable result that would refute it. *A prediction with no falsifier is rejected and rewritten.*
- At least one prediction should be a **dedicated counter-test** (designed to expose the hypothesis if it is wrong).

Record predictions P1…Pn in the state file.

### Phase 3: Inductive Verification (Inductive role — Codex by default)

Hand the predictions to the inductive role with a strict mandate:

- **Re-read the corpus from disk**; ignore any cached content.
- For large data, **process with scripts** (node/python/ripgrep), not by reading raw.
- For **each** prediction: gather instances, produce a **number** (count / rate / measure), and **actively search for counterexamples**.
- Quote 3–5 short representative instances per prediction (verbatim, trimmed).
- Render a verdict per prediction: **【支持 / 部分支持 / 反証】** with the number and quotes.
- End with **【帰納役の総合所見】**: how H should be updated, and — most importantly — **2–3 nuances or counterexamples the deductive role likely missed.** Do not flatter the hypothesis.

In **codex mode** this is delegated via MCP (`mcp__codex__codex`, `sandbox: "read-only"`) or `codex exec`. In **claude-only mode** Claude performs the empirical pass itself, but must still script over the real corpus and hunt counterexamples.

### Phase 4: Arbitration (Arbiter role — Claude)

Reconcile predictions against evidence:

1. Build a **scorecard**: each Pi → predicted vs observed → 支持/部分支持/反証.
2. Explicitly flag every **partially-falsified or falsified** prediction and name **where the deductive framing over- or under-reached.**
3. Integrate the inductive role's "missed nuances" — these usually carry the real refinement.
4. Produce **H′**: the updated hypothesis, rephrased to survive the evidence.
5. Assign a **confidence** (low/medium/high) with the reason (how robust, how independent the evidence was).

### Phase 5: Iterate or Conclude

- If **H′ changed materially** and `max_rounds` not reached → loop back to **Phase 2** with H′ as the new hypothesis.
- If **H′ is stable** (converged) → conclude.

**Stop conditions:**
- Convergence: H′ ≈ H (no material change between rounds).
- `max_rounds` reached (default: 3).
- User requests stop.

### Phase 6: Conclude and Report

Summarize: final hypothesis H_final, the prediction scorecard, the key counterexamples that forced changes, the confidence level, and a short **"what the original framing missed"** section (the loop's main value).

## Role Distribution

| Variant / Mode | Hypothesis (abduction) | Predictions (deductive) | Empirical Test (inductive) | Arbitration |
|------|------|------|------|------|
| default · `codex` | user / Claude | Claude | **Codex** (independent, read-only, grounded) | Claude |
| default · `claude-only` | user / Claude | Claude | Claude (must still script over real corpus) | Claude |
| **`--abduce`** (codex only) | **Codex** (from corpus) | Claude | **Codex** (separate thread) | Claude (+ mandatory disk recompute) |

- **Default mode**: `codex` (independence is the design goal; fall back automatically if Codex unavailable).
- **Optional**: `--rotate` swaps deductive/inductive authorship between rounds to further reduce single-model bias.
- **`--abduce` (abduction variant)**: Codex *generates* the hypothesis from the corpus (abduction), Claude derives predictions and arbitrates. This removes the default variant's weakness — that Claude grades its own hypothesis — by making author (Codex) ≠ arbiter (Claude). Requires `mode = codex`; incompatible with `--mode claude-only` and `--rotate` (both error). See **Design principles #6** for the independence guards that keep "Codex authors *and* tests" honest.

## State File

Loop state is persisted to `tmp/dialectic-loop/<task-id>.md`:

Default variant uses `dialectic-loop/v1`; the `--abduce` variant uses `dialectic-loop/v2`, which **adds optional fields** (a v1 file is read as `variant: default` with the new fields absent — fully backward compatible).

```yaml
---
schema: dialectic-loop/v1
task_id: 20260620-090000-12345
created: 2026-06-20T09:00:00Z
claim: "masuP9 holds judgments provisionally but cuts actions decisively"
corpus: "/home/masup9/.claude/projects/**/*.jsonl (user utterances)"
mode: codex
round: 1
max_rounds: 3
status: in_progress
confidence: pending
---
```

**`dialectic-loop/v2` (abduction variant)** — superset of v1 with the added fields below. Shown at **creation time** (Phase 0 not yet run); comments note how each field advances:

```yaml
---
schema: dialectic-loop/v2
variant: codex-abduction          # default | codex-abduction
roles: "abduction=Codex, deduction=Claude, induction=Codex, arbitration=Claude"
phase: abduction                  # abduction → deductive → inductive → arbitration → report
original_claim: ""                # user-supplied claim if any (else empty — Codex abduces)
confirmed_hypothesis: ""          # set in Phase 0b (selection)
abduction_status: pending         # pending → done (set AFTER candidates persisted)
hypothesis_status: pending        # pending → confirmed (after Phase 0b)
abduction_thread_id: ""           # set in Phase 0a (empty/bash-exec in Bash mode)
induction_thread_id: ""           # set in Phase 3 — MUST differ from abduction_thread_id
confidence: pending               # → low | medium | high (Phase 4)
evidence_scope: pending           # → confirmatory | exploratory_in_sample (Phase 4)
claim: ""                         # v2: mirrors confirmed_hypothesis once Phase 0b selects it (empty before); original_claim holds the user seed
# ...plus the remaining v1 fields (task_id, created, corpus, mode, round, max_rounds, status)
---

# ...candidates are persisted under a `## Abduction` / `### Candidates` section in the body.

# Dialectic Loop: <claim>

## Round 1

### Deductive — Predictions
- P1: ... | 支持条件: ... | 反証条件: ...
- P2: ... (counter-test) | ...

### Inductive — Evidence (Codex)
- P1: 【支持】rate=72% — "quote", "quote"
- P2: 【部分支持】27.7% — "quote"
- 総合所見: ...（演繹役が見落とした反例: ...）

### Arbitration
- Scorecard: P1 支持 / P2 部分支持（演繹役が過大評価）/ ...
- H′: ...
- Confidence: medium — independent extraction, N=423

## Round 2
...
```

## Safety Guards

- Inductive verification runs **read-only** (`sandbox: "read-only"`); it observes, it does not mutate.
- The inductive role must **re-read from disk** and **script over large corpora** (no raw-dump reading, no cached content).
- Confirm before any file modification (this skill is analytical; writes are limited to the state file and the final report).
- Set per-delegation timeout: `min(wait_timeout + 60, 600) * 1000` ms for `codex exec`.
- **Abduction variant only:** the arbiter's disk recompute is **mandatory** (not optional); the induction thread must be **distinct** from the abduction thread; and on Codex failure, never silently fall back to claude-only (would break author≠verifier — see command Error Handling).

## Output Format

### Progress Display

```
Dialectic Loop — Round 2 / 3
Claim: masuP9 holds judgments provisionally but cuts actions decisively

Predictions:
  [✓] P1 hedged judgments dominant      → 支持   (72%)
  [~] P2 judgment coupled to verify     → 部分支持 (28%)  ← deductive over-reach
  [✓] P3 no principle-only commands     → 支持   (0 found)
  [✓] P4 decision deferral present      → 支持   (8)

H′: provisional in belief, decisive in action; verifies selectively, not reflexively
Confidence: medium  |  Convergence: pending (H changed this round)
```

### Completion Report

```
Dialectic Loop Complete
=======================
Claim (H):     <original>
Refined (H′):  <updated hypothesis that survived the evidence>
Confidence:    medium (independent verifier, N=423, 1 prediction partially falsified)

Scorecard:
  P1 支持 (72%) · P2 部分支持 (28%) · P3 支持 (0) · P4 支持 (8)

What the original framing missed:
  1. ...
  2. ...

Loop log: tmp/dialectic-loop/<task-id>.md
```

## Invoking the Skill

Use the `/dialectic-loop` command:

```bash
# Basic — validate a claim against a corpus
/dialectic-loop "User X holds judgments provisionally but cuts actions decisively" --corpus "~/.claude/projects/**/*.jsonl"

# Mode + rounds
/dialectic-loop --mode claude-only --max-rounds 2 "This API degrades under concurrency"

# Rotate authorship to reduce bias
/dialectic-loop --rotate "Codebase favors composition over inheritance"

# Abduction variant — let Codex generate the hypothesis from the corpus (claim optional)
/dialectic-loop --abduce --corpus "scripts/**/*.sh"

# Japanese
/dialectic-loop 「この傾向分析の仮説をログで検証して精緻化して」
```

## Compact Recovery

If compacted mid-loop:

1. Run `TaskList` to see progress.
2. Read the state file: `tmp/dialectic-loop/<task-id>.md`.
3. Resume from the current phase based on `round` and which sections are filled.

| State | Resume at |
|-------|-----------|
| `variant: codex-abduction`, `abduction_status` ≠ done | Phase 0a (regenerate candidates, new abduction thread) |
| candidates present, `hypothesis_status` ≠ confirmed | Phase 0b (selection) |
| H confirmed, no predictions | Phase 2 (Deductive) |
| predictions present, no evidence | Phase 3 (Inductive) |
| evidence present, no arbitration | Phase 4 (Arbitration) |
| arbitration present, H′ changed, rounds remain | Phase 2 (next round) |
| H′ converged or max_rounds reached | Phase 6 (Report) |

**Thread recovery (abduction variant):** if `abduction_thread_id` is lost but candidates are recorded, do not regenerate it; if `induction_thread_id` is lost mid-loop, start a fresh induction thread from the current round's H + predictions + corpus rule and recompute that round (never reuse the abduction thread).

## References

Detailed templates in `references/`:

- **`abduction-template.md`** — the prompt handed to Codex in the `--abduce` variant's Phase 0 to generate competing candidate hypotheses from the corpus.
- **`prediction-template.md`** — structure for the deductive role's falsifiable predictions.
- **`induction-verification-template.md`** — the prompt handed to the inductive role (Codex), including the counterexample-hunting mandate.
