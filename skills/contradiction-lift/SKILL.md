---
name: Contradiction Lift
description: 'This skill should be used when the user wants to "synthesize two competing solutions without averaging", "resolve a design/value disagreement by lifting to a higher frame", "止揚 / アウフヘーベン", "矛盾を止揚", "独立案を統合", "平均化せず統合", "contradiction lift", "sublate competing designs", or has two good-but-divergent answers to the same question and wants a higher-order resolution (a selection mechanism) or an honest aporia — not a compromise. NOTE: Use this when two independent solutions diverge and you want to PRESERVE both truth-moments while lifting to a higher frame. Use devils-advocate to stress-test ONE proposal with an assigned opponent, strong-inference to find an unknown cause, and dialectic-loop to validate a claim against a real corpus.'
---

# Contradiction Lift Skill

Have Claude and Codex **independently solve the same problem**, surface the contradiction from where their answers diverge, and pursue **Aufhebung (sublation / 止揚)** — not averaging, not compromise, but a lift that **preserves both truth-moments** while raising them to a higher frame. The output is a **selection mechanism** (when does A win, when does B win, and why) or an **honest aporia** (this cannot be lifted; here is the irreducible axis).

## Overview

The single most important design fact: **the enemy of Aufhebung is not conflict — it is averaging** (a watered-down middle ground). Left alone, two LLMs fail in two ways: premature agreement (mutually sycophantic "great point, I agree" → instant collapse), or sterile gridlock (debate where each just re-states its position). Telling them to "find the middle" produces the worst outcome — a diluted average. So almost the entire mechanism is spent **keeping the process out of averaging and out of gridlock, and forcing a real lift**.

A Contradiction Lift run:

1. **Fixes the question** (Decision Contract) so interpretation gaps are not mistaken for contradictions.
2. **Seals two independent solutions** (Claude + Codex, neither sees the other first).
3. **Maps the divergence** by type and names the **load-bearing** premises (flip-test).
4. **Routes** each disagreement: empirically decidable → Codex runs a *discriminating* experiment; the rest → preservation.
5. **Preserves** each side via mutual steelman (accept / repair-once handshake).
6. **Constructs a lift** — a selection mechanism `f(C) → A | B | N`, not a position.
7. **Audits the lift** against 7 tests; if it fails twice, declares an honest aporia.

## Comparison with sibling skills

| Aspect | Strong Inference | Devil's Advocate | Dialectic Loop | **Contradiction Lift** |
|--------|------------------|------------------|----------------|------------------------|
| Purpose | Find an unknown cause | Stress-test one proposal | Validate/refine a claim vs data | **Lift two divergent solutions to a higher frame** |
| Contradiction | competing hypotheses | **assigned** (external red team) | prediction vs evidence | **emergent** (two independent solves diverge) |
| Engine of truth | decisive experiment | adversarial critique | counterexample hunting on corpus | **preservation + lift, with empirical routing** |
| Output | root cause | verdict (APPROVE/…) | refined hypothesis H′ | **selection mechanism, or honest aporia** |
| Success ≠ | — | — | — | **agreement, average, residual-shrink** |
| Best for | debugging | validating a design | trend/claim checking | design/value/direction calls where one experiment can't settle it |

## Prerequisites

- A question with **multiple reasonable decision rules** that a single experiment cannot fully settle (design trade-offs, API/architecture philosophy, product direction, abstraction boundaries). Composite problems are welcome: empirical sub-parts are routed to Codex, and the residual normative core is lifted.
- For `codex` mode: Codex CLI available (`mcp__codex__codex` / `codex exec`). Independence (two *different* models) is the whole point — see Role Distribution.

## Design principles (lessons baked in)

1. **Averaging is the enemy, not conflict.** Never optimize for agreement, average, or residual-shrink. A diluted middle ground is failure, even when it looks like consensus.
2. **Do not pre-assign positions.** Unlike Devil's Advocate (external opponent), let both models *independently* solve the same problem and raise the contradiction from the divergence. Strict ordering: **solve sealed, then reveal** — showing the other's answer first collapses the divergence into anchoring.
3. **Name the contradiction before lifting.** The real conflict is usually at the level of an unstated **load-bearing premise**, not the surface conclusion. Surfacing that premise is half of the lift.
4. **Force the preservation moment.** Before lifting, each side must steelman the other in full (Aufhebung's "preserve"), then identify the **irreducible incompatible core** that survives mutual steelman. Averaging fails because it merges before isolating this residual.
5. **Let the object adjudicate what it can.** Empirically decidable disagreements are *not debated* — Codex runs a **discriminating** experiment (pre-register "if X then A, if Y then B" before running). The object (code/data) asserts itself. Only execution-undecidable disagreements go to the lift.
6. **A third role must be separate from the parties.** Letting a party synthesize produces sycophantic averaging. Mapping, lift construction, and audit run on **fresh threads with anonymized inputs**. Honest limitation: with only two models the "third party" is approximated, not real (see Role Distribution).
7. **Allow an honest aporia.** Forcing a synthesis when none exists disguises an average as a "synthesis". If the trade-off is genuinely irreducible, "this cannot be lifted; the axis is X" is worth more than a fake third term. This escape is the last guard against fleeing into averaging.

## Workflow Phases

State machine: `contract → sealed → mapped → adjudicated → preserved → lifted → accepted | aporia`. A third terminal, `no_material_divergence`, can be reached from `mapped` (see Phase 2) — used when the two solutions share the same load-bearing core, so there is nothing to lift.

### Phase 0: Decision Contract

Fix the shared frame **first**: the question `Q`, success conditions, constraints, immovable requirements, empirically observable variables, and the required decision format. If this is vague, a mere interpretation gap will be mis-read as a philosophical contradiction. Confirm with the user.

### Phase 1: Sealed Solutions (Claude + Codex, independent)

Both models solve `Q` against the **same Decision Contract**, without seeing each other's work. Each submits the **decision function, not just a conclusion**, using `references/sealed-solution-template.md`: conclusion, decision rule, causal model, load-bearing assumptions, invariants to protect, rejected alternatives, the observation that would flip the conclusion, confidence. Solver A = Claude; Solver B = Codex (fresh thread). **Do not reveal one to the other.**

### Phase 2: Divergence Mapping (anonymized)

A fresh thread receives both solutions **anonymized as X / Y** and builds a disagreement ledger (`references/divergence-map-template.md`), typing each disagreement: `semantic | empirical | causal | normative | constraint | uncertainty`. Load-bearing is decided by the **flip-test**: *change only this premise to the other side — does the conclusion or decision rule change?* A premise that doesn't change the outcome is not core.

**No material divergence:** if the ledger finds **no load-bearing disagreement** (the solutions agree on the core and differ only in dissolvable/minor ways), terminate at `no_material_divergence` and report that both solutions share the load-bearing core — **do not fabricate a contradiction to have something to lift**.

### Phase 3: Adjudication Router

Route each disagreement by type:
- **empirical / observable** → pre-register "if result X → A, if Y → B", then Codex runs a **discriminating** experiment (not "run anything", only experiments with discriminating power).
- **semantic** → normalize the term and dissolve it.
- **constraint** → check against the Decision Contract.
- **normative / unobservable-causal** → send to Preservation.

### Phase 4: Preservation Contract

Each party submits, about the **other**: the conditions under which the other's solution is strongest; the truth-moment lost if it is discarded; a concrete failure of the design without that moment; and the incompatible core that still remains. The other party reviews with **`accept` / `repair once`** only — no unbounded handshake (review target is "is my reasoning represented faithfully?", not "do I agree?").

### Phase 5: Lift Construction (anonymized)

A fresh "Lift Architect" thread builds a **selection mechanism**, not a position: `f(C) → A | B | N` mapping conditions to choices. Required output (`references/lift-audit-template.md`): the conditions→choice mapping; what is conserved from both A and B; any **new** variable / causal relation introduced; a concrete example that selects A, one that selects B, and **one where the choice differs from a simple average**; and failure/falsification conditions. An expanded question `Q'` is **not** mandatory — the lift may instead be a threshold, an ordering, an option value, or a reversibility-staged decision (broadening the question can itself be an abstraction-escape).

### Phase 6: Lift Audit

An **independent** thread (not the one that built the lift) runs all 7 tests. All must pass for `accepted`; on failure, reconstruct **once**, and if it still fails, declare `aporia`.

**The 7 tests** (these close the holes: a useless new variable, fabricated scenarios, a mere condition-branch router masquerading as a lift):

1. **Conservation** — the conserved moments of both A and B are traceable.
2. **Discrimination** — the mechanism actually selects differently under different conditions.
3. **Novelty** — there is a decision variable / relation / procedure absent from both originals.
4. **Non-vacuity** — it does not end at "it depends"; the conditions are observable.
5. **Dominance** — in at least one scenario it out-explains/out-decides A, B, **and** the simple compromise.
6. **Falsifiability** — you can state the conditions under which the lift fails.
7. **Feasibility** — the application cost does not eat the benefit.

Especially require the **causal mechanism**: *why* does that condition change the choice?

## Role Distribution

| Role | Assignee | Notes |
|------|----------|-------|
| Solver A | Claude (native) | sealed |
| Solver B | Codex (fresh thread, `read-only`) | sealed; never sees A first |
| Mapper | fresh Codex thread (anonymized X/Y) | typed divergence + flip-test |
| Empirical Arbiter | Codex execution (`read-only`; `workspace-write` only if an experiment must build/run) | pre-registered discriminating experiments |
| Lift Architect | fresh thread (anonymized) | builds the selection mechanism |
| Meta Auditor | independent thread (did **not** build the lift) | 7-test audit; cross-checked |

**Honest limitation on independence.** There are only two models. The "third-party" roles (Mapper, Lift Architect, Meta Auditor) cannot be a literal third model; they are **approximated** by fresh Codex threads with **anonymized inputs and no reasoning history**. State this plainly — do not overclaim independence.

- **Default mode**: `codex` (independence of two different models is the design goal).
- **`claude-only` mode**: degraded — Claude can run two passes, but the core (two *different* models diverging) is lost. Warn explicitly and recommend `codex` mode.

## State File

Persisted to `tmp/contradiction-lift/<task-id>.md` (survives compaction):

```yaml
---
schema: contradiction-lift/v1
task_id: 20260621-090000-12345
created: 2026-06-21T09:00:00Z
question: "Should the loop stop on fixed rounds or convergence detection?"
mode: codex
state: contract            # contract|sealed|mapped|adjudicated|preserved|lifted|accepted|aporia|no_material_divergence
solver_b_thread_id: ""     # Codex thread for Solver B (bash-exec-solver in Bash mode)
mapper_thread_id: ""       # fresh anonymized thread (bash-exec-mapper)
lift_thread_id: ""         # Lift Architect (bash-exec-lift)
audit_thread_id: ""        # Meta Auditor — MUST differ from lift_thread_id (bash-exec-audit)
empirical_arbiter: pending # pending|done|not_applicable (no empirical disagreements)
lift_attempts: 0
max_lift_attempts: 2
outcome: pending           # pending|lifted|aporia|no_material_divergence
---

# Contradiction Lift: <question>

## Decision Contract
## Sealed Solutions
### Solution A (Claude)
### Solution B (Codex)
## Divergence Ledger
## Adjudication
## Preservation
## Lift
## Audit
```

## Safety Guards

- Solver B / Mapper / Empirical Arbiter run **read-only** by default (`sandbox: "read-only"`); only an experiment that must build/run uses `workspace-write`, and only with confirmation.
- **Sealing is load-bearing**: never pass Solution A into Solver B's prompt (or vice versa) before both are sealed.
- **Anonymize** A/B → X/Y for Mapper / Lift Architect / Meta Auditor, and do not pass prior reasoning history.
- **Role threads must be mutually distinct** where independence matters: `mapper_thread_id ≠ solver_b_thread_id`, the Lift Architect thread ≠ mapper/solver, and the auditor ≠ architect (`audit_thread_id ≠ lift_thread_id`). Each independence-bearing role gets its **own** fresh thread (in Bash mode, the distinct `bash-exec-<role>` sentinels preserve this invariant).
- Confirm before any file modification (this skill is analytical; writes are limited to the state file and the final report).
- Set per-delegation timeout: `min(wait_timeout + 60, 600) * 1000` ms for `codex exec`.

## Output Format

Three possible outcomes, all first-class:

**Accepted lift:**
```
Contradiction Lift — ACCEPTED
Question:  <Q>
Lift:      <selection mechanism — f(C) → A | B | N>
Conserves: A: <...> | B: <...>
New:       <variable/relation absent from both originals>
Selects A when: <example>   Selects B when: <example>
Differs from average when: <example>
Fails if:  <falsification condition>
Audit:     7/7 passed
Log: tmp/contradiction-lift/<task-id>.md
```

**Honest aporia:**
```
Contradiction Lift — APORIA (not lifted)
Question:  <Q>
Irreducible axis: <the trade-off that cannot be sublated>
A is right when: <condition C1>   B is right when: <condition C2>
Why no lift: <which audit test failed twice, and why>
Log: tmp/contradiction-lift/<task-id>.md
```

**No material divergence:**
```
Contradiction Lift — NO MATERIAL DIVERGENCE
Question:  <Q>
Shared load-bearing core: <what both A and B agree on>
Minor/dissolvable differences: <semantic/style only — not lifted>
Note: nothing to lift; a contradiction was not manufactured.
Log: tmp/contradiction-lift/<task-id>.md
```

## Invoking the Skill

```bash
# Lift two independent solutions to an execution-undecidable question
/contradiction-lift "Should dialectic-loop stop on fixed rounds or convergence detection?"

# Claude-only (degraded — independence is weak; codex recommended)
/contradiction-lift --mode claude-only "Composition vs inheritance for this module hierarchy"

# Cap lift retries
/contradiction-lift --max-lift-attempts 1 "Monorepo vs polyrepo for this org"
```

## Compact Recovery

1. `TaskList` for progress; read `tmp/contradiction-lift/<task-id>.md`; read `state` / `*_thread_id` / `lift_attempts`.
2. Resume by `state`:

| State | Resume at |
|-------|-----------|
| `contract` | Phase 0 (or Phase 1 if contract present) |
| `sealed` | Phase 2 (Divergence Mapping) |
| `mapped` | Phase 3 (Adjudication Router) |
| `adjudicated` | Phase 4 (Preservation) |
| `preserved` | Phase 5 (Lift Construction) |
| `lifted` | Phase 6 (Audit) |
| `accepted` / `aporia` / `no_material_divergence` | Report |

3. **Thread recovery**: a fresh-thread role whose id is lost is simply restarted from its persisted inputs (the ledger / sealed solutions / lift are on disk). Keep `audit_thread_id ≠ lift_thread_id` on restart.

## References

Detailed templates in `references/`:

- **`sealed-solution-template.md`** — the schema each solver fills in Phase 1 (decision function, load-bearing assumptions, flip observation).
- **`divergence-map-template.md`** — the anonymized disagreement ledger (typed divergence + flip-test) for Phase 2.
- **`lift-audit-template.md`** — the Lift Construction output format and the Phase 6 seven-test audit + aporia criteria.
