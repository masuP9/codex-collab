# Divergence Map Template (Phase 2)

A **fresh** thread (a different role from the solvers) receives the two sealed solutions
**anonymized as X / Y** and builds a disagreement ledger. The goal is not to pick a winner but
to **name the contradiction precisely** — typed, and down to the load-bearing premise.

## Prompt Template (given to the Mapper, anonymized)

```markdown
{{LANG_DIRECTIVE}}You are mapping the disagreement between two independent solutions to the
same question. They are anonymized as **X** and **Y**; do not guess who wrote them and do not
favor either. Re-read referenced files from disk. Your job is to *characterize* the divergence,
not resolve it.

## Decision Contract
{{DECISION_CONTRACT}}

## Solution X
{{SOLUTION_X}}

## Solution Y
{{SOLUTION_Y}}

## Your task
Build a disagreement ledger. For each distinct disagreement:
1. **Type** it: `semantic | empirical | causal | normative | constraint | uncertainty`.
2. **Flip-test for load-bearing**: change ONLY this premise to the other side — does X's (or Y's)
   conclusion or decision rule change? If nothing changes, it is **not** core; mark it minor.
3. State the **underlying premise** each side holds (often unstated in the conclusions).

## Output format

\`\`\`markdown
| # | disagreement | type | X premise | Y premise | flip-test result | load-bearing? |
|---|--------------|------|-----------|-----------|------------------|---------------|
| 1 | ...          | causal | ... | ... | flipping → conclusion changes | yes |

### Load-bearing core
- {the 1–3 disagreements that actually drive the divergence}

### Reducible (route or dissolve)
- {semantic → normalize; empirical → experiment; constraint → check contract}
\`\`\`
```

## Disagreement types

- **semantic** — different reading of the question or a term (dissolve by normalizing).
- **empirical** — different prediction about a fact (route to a discriminating experiment).
- **causal** — different model of *why* (often load-bearing; may be observable or not).
- **normative** — different priority among values (goes to Preservation/Lift).
- **constraint** — different belief about what is allowed/required (check the Contract).
- **uncertainty** — different risk tolerance / confidence (often a threshold the lift can encode).

## Rules

1. **Anonymized and even-handed** — X/Y only; surface premises for both symmetrically.
2. **Flip-test decides load-bearing**, not how big the disagreement *sounds*.
3. Separate the **load-bearing core** (goes to Adjudication/Preservation) from the **reducible** rest (route or dissolve) — do not send dissolvable semantic gaps to the lift.
