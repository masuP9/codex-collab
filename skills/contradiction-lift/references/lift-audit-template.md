# Lift Construction & Audit Template (Phases 5–6)

The lift is a **selection mechanism**, not a position. The audit exists to stop the most common
fakes: a useless new variable, fabricated discriminating scenarios, and a plain condition-branch
router dressed up as a synthesis. The architect and the auditor must be **different threads**.

## Phase 5 — Lift Construction (Lift Architect, anonymized inputs)

```markdown
{{LANG_DIRECTIVE}}You are constructing a *lift* (Aufhebung) over two independent solutions X and Y
and their preserved truth-moments. Do NOT average or split the difference. Build a **selection
mechanism** that preserves both and rises above them.

## Inputs
- Decision Contract: {{DECISION_CONTRACT}}
- Preserved core (X): {{PRESERVED_X}}
- Preserved core (Y): {{PRESERVED_Y}}
- Irreducible disagreements: {{RESIDUAL}}

## Required output

\`\`\`markdown
- **Selection mechanism f(C) → A | B | N**: {map conditions C to the choice; A=X's answer, B=Y's, N=neither/new}
- **Conserves from X**: {truth-moment kept}   **Conserves from Y**: {truth-moment kept}
- **New element**: {a decision variable / causal relation / procedure absent from BOTH originals}
- **Causal mechanism**: {WHY does the condition change the choice? — the mechanism, not a rule restated}
- **Selects A when**: {concrete example}
- **Selects B when**: {concrete example}
- **Differs from a simple average when**: {concrete example where f makes a choice the diluted middle would not}
- **Q' (optional)**: {expanded question, IF one is genuinely needed — else a threshold/ordering/option-value/reversibility-staged decision}
- **Fails if**: {falsification condition}
\`\`\`
```

> `Q'` is **not** mandatory. Broadening the question can be an abstraction-escape. A threshold, an
> ordering, an option value, or a reversibility-staged decision is often the real lift.

## Phase 6 — Lift Audit (Meta Auditor, MUST differ from the architect)

Run **all 7 tests**. Every one must pass for `accepted`. On any failure, the architect reconstructs
**once**; if it still fails, declare `aporia`.

```markdown
| # | Test | Pass? | Evidence |
|---|------|-------|----------|
| 1 | Conservation — both X and Y truth-moments traceable in f (**any uncertified load-bearing moment from Preservation ⇒ Conservation = fail**) | | |
| 2 | Discrimination — f actually selects differently under different C | | |
| 3 | Novelty — a decision variable/relation/procedure absent from both originals | | |
| 4 | Non-vacuity — not "it depends"; the conditions C are observable | | |
| 5 | Dominance — in ≥1 scenario f out-explains/out-decides A, B, AND the simple compromise | | |
| 6 | Falsifiability — the conditions under which the lift fails are stated | | |
| 7 | Feasibility — application cost does not eat the benefit | | |

**Causal check**: is there a stated mechanism for WHY each condition changes the choice? (yes/no)
**Verdict**: accepted (**7/7 AND causal check = yes**) | reconstruct (attempt < max) | aporia (failed at max attempts). A 7/7 with `causal check = no` is **not** accepted — a mechanism-less condition-branch router is not a lift.
```

## Aporia criteria (a first-class outcome)

Declare an **honest aporia** when, after `max_lift_attempts`, the lift still fails the audit —
typically because:

- **Dominance** never holds (the lift never beats A, B, and the average together) → it is an average in disguise; or
- **Novelty** is absent (only a condition-branch router, no new element); or
- **Non-vacuity** fails (conditions are not observable — "it depends" with no handle).

Report the **irreducible axis** instead: *A is right when C1, B is right when C2, and no observable
mechanism selects between them at a higher level.* This is more valuable than a manufactured third term.
