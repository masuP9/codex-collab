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
2. **Seals two independent solutions** — a fresh Claude subagent (Solver A) and Codex (Solver B) solve **in parallel**; the orchestrator dispatches both and reads neither until both return, so sealing is **structural** (the orchestrator never authors a solution it could contaminate).
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
2. **Do not pre-assign positions.** Unlike Devil's Advocate (external opponent), let both models *independently* solve the same problem and raise the contradiction from the divergence. Strict ordering: **solve sealed, then reveal** — showing the other's answer first collapses the divergence into anchoring. **Sealing is structural, not disciplinary:** the orchestrator must not author Solution A itself (while orchestrating it would already have seen Solver B). Solver A runs as a **fresh Claude subagent**, dispatched **in parallel** with Solver B (Codex); the orchestrator reads neither until both are sealed. The orchestrator's job is dispatch / anonymize / route / persist — never solve or synthesize.
3. **Name the contradiction before lifting.** The real conflict is usually at the level of an unstated **load-bearing premise**, not the surface conclusion. Surfacing that premise is half of the lift.
4. **Force the preservation moment.** Before lifting, each side must steelman the other in full (Aufhebung's "preserve"), then identify the **irreducible incompatible core** that survives mutual steelman. Averaging fails because it merges before isolating this residual.
5. **Let the object adjudicate what it can.** Empirically decidable disagreements are *not debated* — Codex runs a **discriminating** experiment (pre-register "if X then A, if Y then B" before running). The object (code/data) asserts itself. Only execution-undecidable disagreements go to the lift.
6. **A third role must be separate from the parties.** Letting a party synthesize produces sycophantic averaging. Mapping, lift construction, and audit run on **fresh, anonymized roles** — either a **fresh Claude subagent** (own context window, no reasoning history) or a **fresh Codex thread**. Pick the assignee by *which independence the role needs* (see "Independence: two kinds"): subagents buy **context-independence**; only the Claude/Codex split **approximates prior-independence** (different model family — never a full guarantee).
7. **Allow an honest aporia.** Forcing a synthesis when none exists disguises an average as a "synthesis". If the trade-off is genuinely irreducible, "this cannot be lifted; the axis is X" is worth more than a fake third term. This escape is the last guard against fleeing into averaging.

## Independence: two kinds

Every non-party role needs *some* independence, but there are **two distinct kinds**, and they come from different places:

| Kind | What it prevents | Source |
|------|------------------|--------|
| **Context-independence** | sealing breaches, anchoring, orchestrator contamination, history leakage | a **fresh context** — a Claude **subagent** (own window, no reasoning history) *or* a fresh Codex thread |
| **Prior-independence** | *correlated blind spots* — two solvers from the same training distribution making the same error and "agreeing" | a **different model family** — approximated (not guaranteed) by the **Claude × Codex** split; shared training data/eval practices mean overlap can remain |

The consequences for role assignment:

- **Solvers (Phase 1) need prior-independence** — the engine is *two different priors diverging* as a liftability detector. Keep **Solver A = Claude subagent, Solver B = Codex**. (Same-model two-pass is the degraded `claude-only` mode.) Subagents additionally make the seal structural (parallel dispatch, orchestrator reads neither first).
- **Verification roles (Mapper, Lift Architect, Auditor) need context-independence first** — a fresh subagent or thread, anonymized, no history. They additionally benefit from **cross-model pairing**: audit a Claude-built lift with a **Codex** auditor and a Codex-built lift with a **Claude** auditor, so a correlated blind spot is **far less likely** to pass both build and audit. A **same-model agreement** (two instances of one model — e.g. the orchestrator and a Claude subagent — reaching the same answer) is **not** independent evidence: shared priors correlate their errors, so never treat "the subagent agreed" as confirmation.

## Workflow Phases

State machine: `contract → sealed → mapped → adjudicated → preserved → lifted → accepted | aporia`. A third terminal, `no_material_divergence`, can be reached from `mapped` (see Phase 2) — used when the two solutions share the same load-bearing core, so there is nothing to lift.

### Phase 0: Decision Contract

Fix the shared frame **first**: the question `Q`, success conditions, constraints, immovable requirements, empirically observable variables, and the required decision format. If this is vague, a mere interpretation gap will be mis-read as a philosophical contradiction. Confirm with the user.

### Phase 1: Sealed Solutions (Claude + Codex, independent, parallel)

Both models solve `Q` against the **same Decision Contract**, without seeing each other's work. Each submits the **decision function, not just a conclusion**, using `references/sealed-solution-template.md`: conclusion, decision rule, causal model, load-bearing assumptions, invariants to protect, rejected alternatives, the observation that would flip the conclusion, confidence.

- **Solver A = a fresh Claude subagent** (Task tool), **not** the orchestrator — so the orchestrator never authors a solution it has already contaminated by seeing Solver B.
- **Solver B = Codex** (fresh thread, `read-only`).
- **Dispatch both in parallel** and collect both sealed results; the orchestrator reads neither until both return. **Do not reveal one to the other**, and never pass Solution A into Solver B's prompt (or vice versa).

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

**Party continuity across phases.** Codex's side continues on `solver_b_thread_id` via `codex-reply` (its thread retains Solution B). Solver A was a **one-shot subagent**, so the Claude-side party actions here (its steelman of B, and its review of B's steelman of A) run as a **fresh Claude subagent re-seeded from the persisted Solution A + Solution B on disk** — identity is reconstructed from the record, not a continued thread. This is sufficient because steelman/review depend only on the *recorded* decision function and assumptions, not on the subagent's private reasoning.

### Phase 5: Lift Construction (anonymized)

A fresh "Lift Architect" thread builds a **selection mechanism**, not a position: `f(C) → A | B | N` mapping conditions to choices. Required output (`references/lift-audit-template.md`): the conditions→choice mapping; what is conserved from both A and B; any **new** variable / causal relation introduced; a concrete example that selects A, one that selects B, and **one where the choice differs from a simple average**; and failure/falsification conditions. An expanded question `Q'` is **not** mandatory — the lift may instead be a threshold, an ordering, an option value, or a reversibility-staged decision (broadening the question can itself be an abstraction-escape).

### Phase 6: Lift Audit

An **independent** role (not the one that built the lift) runs all 7 tests. Prefer **cross-model pairing**: if the Lift Architect was a Claude subagent, run the audit on **Codex** (and vice versa), so a correlated blind spot is far less likely to survive both build and audit. All must pass for `accepted`; on failure, reconstruct **once**, and if it still fails, declare `aporia`.

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

The **orchestrator** (the Claude session running this skill) is dispatch-only: it fixes the contract, dispatches roles, anonymizes inputs, routes, persists state, and reports. It **never** authors a solution, a steelman, a lift, or an audit — those all run in fresh roles.

| Role | Assignee | Notes |
|------|----------|-------|
| Solver A | **fresh Claude subagent** (Task tool, `read-only`) | sealed; dispatched in parallel with Solver B; **not** the orchestrator |
| Solver B | Codex (fresh thread, `read-only`) | sealed; never sees A first |
| Mapper | fresh Claude subagent **or** Codex thread (anonymized X/Y) | typed divergence + flip-test |
| Empirical Arbiter | Codex execution (`read-only`; `workspace-write` only if an experiment must build/run) | pre-registered discriminating experiments |
| Lift Architect | fresh subagent **or** Codex thread (anonymized) | builds the selection mechanism |
| Meta Auditor | independent role that did **not** build the lift — **prefer the opposite model** to the Architect | 7-test audit; cross-model where possible |

**Honest limitation on independence.** A Claude subagent gives **context-independence** (fresh window, no history) but **not prior-independence** — it shares Claude's training distribution, so Claude-subagent roles can carry the same blind spots as the orchestrator. Stronger (still imperfect) prior-independence comes from the **Claude × Codex** split — different model families, though shared training data/eval practices mean overlap can remain. Therefore: keep solvers cross-model, and **pair verification across models** (Claude-built lift → Codex audit, and vice versa) to reduce — not eliminate — correlated errors. Where a role cannot be cross-model (e.g. `claude-only` mode, or no Task tool), say so plainly and **do not treat a same-model agreement as confirmation**.

- **Default mode**: `codex` (independence of two different models is the design goal). Solver A = Claude subagent, Solver B = Codex; verification roles can be cross-model.
- **`claude-only` mode**: degraded — Solver B becomes a **second fresh Claude subagent** (`solver_b_thread_id: claude-subagent-solverB`), and **no role can be cross-model**, so only context-independence is available (the engine — two *different* models diverging — is lost). The subagents still keep sealing structural and avoid anchoring, but treat agreement with extra suspicion. Warn explicitly and recommend `codex` mode.
- **No Task tool** (subagents unavailable): Solver A falls back to the orchestrator (`solver_a_role: orchestrator-fallback`), authored **first** while still blind to Solver B and **persisted** to the state file, **then** Solver B is dispatched (safe because A is already sealed). Authoring A *after* seeing B is forbidden. Sealing degrades from structural to **disciplinary**; verification roles fall back to Codex threads. Note this degradation in the report.

## State File

Persisted to `tmp/contradiction-lift/<task-id>.md` (survives compaction):

```yaml
---
schema: contradiction-lift/v2   # v2 adds *_role fields + claude-subagent actor keys. Reading a v1 file: non-empty *_thread_id ⇒ *_role=codex-thread; empty *_thread_id ⇒ that phase had not run (leave empty, assign on resume); solver_a_role ⇒ orchestrator-fallback (v1's Solver A was the orchestrator).
task_id: 20260621-090000-12345
created: 2026-06-21T09:00:00Z
question: "Should the loop stop on fixed rounds or convergence detection?"
mode: codex
state: contract            # contract|sealed|mapped|adjudicated|preserved|lifted|accepted|aporia|no_material_divergence
solver_a_role: claude-subagent  # claude-subagent (default) | orchestrator-fallback (only when the Task tool is unavailable — sealing degrades to disciplinary)
solver_b_thread_id: ""     # Codex thread for Solver B (bash-exec-solver in Bash mode; claude-subagent-solverB in claude-only mode)
mapper_role: ""            # claude-subagent | codex-thread (anonymized)
mapper_thread_id: ""       # actor key: Codex threadId | bash-exec-mapper | claude-subagent-mapper (subagents get a per-role sentinel so the distinctness invariant still holds)
lift_role: ""              # claude-subagent | codex-thread (anonymized)
lift_thread_id: ""         # actor key: Codex threadId | bash-exec-lift | claude-subagent-lift
audit_role: ""             # claude-subagent | codex-thread — prefer the OPPOSITE model to lift_role
audit_thread_id: ""        # actor key: Codex threadId | bash-exec-audit | claude-subagent-audit — MUST differ from lift_thread_id (per-role sentinels record this distinctness even for two subagents; freshness comes from always dispatching a new subagent)
empirical_arbiter: pending # pending|done|not_applicable|deferred (deferred = an empirical disagreement exists but the experiment can't be run this session)
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

- Solver A subagent / Solver B / Mapper / Empirical Arbiter run **read-only** by default (`sandbox: "read-only"`); only an experiment that must build/run uses `workspace-write`, and only with confirmation.
- **Sealing is structural**: Solver A is a fresh Claude subagent (not the orchestrator), dispatched in parallel with Solver B; the orchestrator reads neither until both return. Never pass Solution A into Solver B's prompt (or vice versa) before both are sealed.
- **The orchestrator never authors** a solution / steelman / lift / audit — each runs in a fresh role. (This is what removes the contamination the old "orchestrator = Solver A" design could not avoid.) **One documented exception:** when the Task tool is unavailable, **Solver A and its Phase 4 party actions** (the Claude-side steelman/review) fall back to the orchestrator (`solver_a_role: orchestrator-fallback`); sealing degrades to disciplinary and the Claude party action loses its fresh-context separation — flag both degradations in the report.
- **Subagents are analysis-only**: a Claude-subagent role must not write files — use a read-only subagent type where available and instruct the subagent to produce only the requested artifact (no edits, no commits). The state file is written by the orchestrator, not the role.
- **Anonymize** A/B → X/Y for Mapper / Lift Architect / Meta Auditor, and do not pass prior reasoning history.
- **Roles must be mutually distinct** where independence matters: Mapper ≠ Solver B, Lift Architect ≠ mapper/solver, and auditor ≠ architect (`audit_thread_id ≠ lift_thread_id`). Each independence-bearing role gets its **own** fresh subagent/thread. The `*_thread_id` field holds a per-role **actor key**: a Codex `threadId`, a `bash-exec-<role>` sentinel (Bash mode), or a `claude-subagent-<role>` sentinel (subagent mode). The unequal comparison (`claude-subagent-lift ≠ claude-subagent-audit`) is a **procedural record that distinct roles were dispatched**, not a runtime proof of a distinct Task invocation — actual freshness is guaranteed by the orchestrator **always dispatching a new subagent for each role** (never reusing one). For the audit, prefer the **opposite model** to the Lift Architect.
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

3. **Role recovery**: every independence-bearing role is **stateless and re-startable from disk** — Codex threads from their persisted inputs (ledger / sealed solutions / lift), and Claude-subagent roles by re-dispatching a fresh subagent re-seeded from the same persisted inputs (one-shot subagents have no thread to resume; this is by design — see Phase 4 "Party continuity"). Keep `audit_thread_id ≠ lift_thread_id` (the per-role actor-key sentinels **record** this distinctness — a procedural record, not a runtime proof; freshness comes from always dispatching a new subagent) on restart.
4. **Schema migration**: a `contradiction-lift/v1` state file has no `*_role` fields. v1 third-party roles were always Codex, so read a **non-empty** `*_thread_id` as `*_role = codex-thread`; an **empty** `*_thread_id` means *that phase had not run yet* (leave it empty and assign the role by the new rules when you reach that phase — do **not** infer `claude-subagent`). `solver_a_role = orchestrator-fallback` (v1's Solver A was the orchestrator). Re-stamp as `v2` on the next write.

## References

Detailed templates in `references/`:

- **`sealed-solution-template.md`** — the schema each solver fills in Phase 1 (decision function, load-bearing assumptions, flip observation).
- **`divergence-map-template.md`** — the anonymized disagreement ledger (typed divergence + flip-test) for Phase 2.
- **`lift-audit-template.md`** — the Lift Construction output format and the Phase 6 seven-test audit + aporia criteria.
