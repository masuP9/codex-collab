# Sealed Solution Template (Phase 1)

Each solver (Claude = A, Codex = B) fills this **independently**, against the same Decision
Contract, **without seeing the other's solution**. Submit the *decision function*, not just a
verdict — comparison in Phase 2 needs structure, and a bare conclusion hides the load-bearing
premises where the real contradiction lives.

## Prompt Template (given to the solver)

```markdown
{{LANG_DIRECTIVE}}You are solving a question independently. You will NOT see any other
solution; answer on your own merits. Re-read any referenced files from disk.

## Decision Contract
{{DECISION_CONTRACT}}
<!-- question Q, success conditions, constraints, immovable requirements,
     observable variables, required decision format -->

## Your task
Produce a structured solution using the schema below. Give the **decision rule**, not only a
conclusion. Be concrete and falsifiable; no hedging-to-the-middle.

## Output schema

\`\`\`markdown
- **Conclusion**: {one-line answer to Q}
- **Decision rule f**: {the rule/procedure that produces the conclusion — "given <inputs>, choose <X> because <criterion>"}
- **Causal model**: {why this works — the mechanism, not just correlation}
- **Load-bearing assumptions**: {the premises that, if false, would change the conclusion — list them explicitly}
- **Invariants to protect**: {what must not be sacrificed}
- **Rejected alternatives**: {what you considered and discarded, with the reason}
- **Flip observation**: {the single observation that would flip your conclusion}
- **Confidence**: {low | medium | high} + {why}
\`\`\`
```

## Rules

1. **Decision rule over conclusion.** "Use X" is not enough; give the rule that *generates* "use X" so Phase 2 can compare mechanisms, not slogans.
2. **List load-bearing assumptions explicitly.** The contradiction usually lives here. Hiding them defeats the whole run.
3. **State a flip observation.** A solution with nothing that could flip it is not falsifiable — push back and rewrite.
4. **No pre-emptive compromise.** Do not soften toward an imagined middle ground; solve the question as you actually see it. Divergence is the raw material.
