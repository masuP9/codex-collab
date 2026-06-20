# Prediction Template (Deductive Role)

The deductive role takes the hypothesis **as given** and derives falsifiable predictions.
Every prediction must be measurable against the corpus and must carry an explicit falsifier.

## Per-prediction structure

```markdown
### P{n}: {one-line prediction}

- **If H is true, we should observe:** {concrete, countable phenomenon in the corpus}
- **支持条件 (support):** {the measurable result that confirms — e.g. "hedge rate > 50% among judgment utterances"}
- **反証条件 (falsifier):** {the measurable result that refutes — e.g. "hedge rate < 25%, or flat assertions dominate"}
- **Measure:** {what the inductive role should compute — a count, a rate, a ratio}
- **Type:** support-test | counter-test
```

## Rules

1. **No falsifier → reject the prediction and rewrite it.** A claim that cannot fail is not a prediction.
2. **Include at least one `counter-test`** — a prediction specifically designed to expose the hypothesis if it is false (e.g. "if X were a rigid rule-follower, we'd find N principle-only commands — count them").
3. **Keep each prediction independently measurable** — the inductive role tests them one at a time.
4. **Prefer rates over absolute counts** where corpus size varies, so results are comparable across rounds.
5. **State the corpus and extraction rule once**, so the inductive role measures the same population.

## Worked example

```markdown
### P2: Proposals are coupled with verification (counter-test for "verifies reflexively")

- If H is true, we should observe: most rule/decision proposals in the same message also request a check.
- 支持条件: coupling rate > 60% of proposal-utterances.
- 反証条件: coupling rate < 35% → H over-states reflexive verification.
- Measure: (# proposal-utterances that co-occur with a verify request) / (# proposal-utterances).
- Type: counter-test
```
