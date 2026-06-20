# Induction Verification Template (Inductive Role → Codex)

This prompt is handed to the inductive role (Codex in `codex` mode) in Phase 3.
Its purpose is an **independent empirical test** of the deductive role's predictions, with active counterexample hunting. Fill the `{{...}}` placeholders.

## Prompt Template

```markdown
{{LANG_DIRECTIVE}}You are the **inductive (empirical) role** in a Dialectic Loop. The deductive role
(another model) authored a hypothesis and predictions. Your job is to test them against
the real corpus and, crucially, to **hunt for counterexamples**. Do not flatter the
hypothesis — a counterexample you find is worth more than a confirmation.

**IMPORTANT**: Re-read all data from disk. Ignore any cached content from earlier in this
session. The corpus is large — process it with scripts (node/python/ripgrep), never by
reading raw dumps.

## Corpus

{{CORPUS_PATHS_AND_EXTRACTION_RULES}}
<!-- e.g. /home/.../**/*.jsonl, one JSON object per line; keep obj.type==='user' with
     obj.message; drop messages whose content is entirely tool_result; concat text parts;
     drop lines starting with <local-command|Caveat:|<command-|<task-notification|<bash- -->

## Hypothesis under test (H)

{{HYPOTHESIS}}

## Predictions to verify

{{PREDICTIONS_P1_PN}}
<!-- each with its 支持条件 / 反証条件 / Measure -->

## Your task

For **each** prediction:
1. Compute the **Measure** (a number: count / rate / ratio) by scripting over the corpus.
2. Quote **3–5 short verbatim instances** (trimmed) that illustrate the result.
3. **Actively search for counterexamples** to the prediction and report how many you found.
4. Render a verdict: **【支持 / 部分支持 / 反証】** with the number.

Then provide:

### 【帰納役の総合所見】
- How should H be updated based on the evidence?
- **2–3 nuances or counterexamples the deductive role likely missed** (this is the most
  valuable part — be specific, cite numbers/quotes, no sycophancy).

## Response format

\`\`\`markdown
**P1** 【支持/部分支持/反証】 measure=...  
- "quote" / "quote" / "quote"  
- counterexamples found: N (...)

**P2** ...

### 【帰納役の総合所見】
- update: ...
- missed #1: ...
- missed #2: ...
\`\`\`

---
status: stop
---
```

## MCP invocation (codex mode)

```
mcp__codex__codex(
  prompt: "<filled template above>",
  developer-instructions: "<language directive>",
  sandbox: "read-only",
  cwd: "<corpus root>"
)
```

For round 2+, continue the same **induction** thread with `mcp__codex__codex-reply(threadId, prompt)`
so the inductive role retains the prior round's measurements.

## Abduction variant (`--abduce`) note

When the hypothesis was abduced by Codex (Phase 0), the inductive role still runs here as an
independent test — but with the following extra rules:

- **Fresh, isolated thread.** Start the induction on a thread **distinct** from the abduction
  thread. Pass only the confirmed H, the predictions, and the corpus rule — **do not** reveal
  that Codex authored H, nor the abduction thread's candidates/rationale/confidence. The
  verifier should test H on its merits, blind to its origin.
- **Origin-neutral wording.** Replace the template's opening line ("The deductive role (another
  model) authored a hypothesis and predictions") with an origin-neutral one, e.g.
  *"The hypothesis (H) and predictions below were prepared outside this thread."* Do not assert
  who authored H (Codex authored it in this variant; saying "another model" would be false).
- **Round 2+ continues the induction thread only** (never the abduction thread).
- The arbiter's disk recompute is mandatory in this variant, and same-corpus discovery→validation
  is marked `evidence_scope: exploratory_in_sample`.

## Quality bar

- A prediction reported without a number is **not** verified — push back / re-run.
- "部分支持" must state *which part* held and which did not (this is what the arbiter needs).
- If the inductive role cannot access the corpus, it must say so rather than guess.
