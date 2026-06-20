# Abduction Template (Abduction Role → Codex)

Used in the `--abduce` variant's **Phase 0a** to have Codex *generate* candidate hypotheses
from the corpus. Codex runs this on a **dedicated abduction thread** (kept separate from the
later induction thread). Fill the `{{...}}` placeholders.

## Prompt Template

```markdown
{{LANG_DIRECTIVE}}You are the **abduction (hypothesis-generation) role** in a Dialectic Loop.
Your job is to look at the real corpus and propose **competing candidate hypotheses** worth
testing — not to test them. A different model (the deductive role) will design the tests, and
the arbiter will judge; so make the candidates sharp and falsifiable, not safe.

**IMPORTANT**: Re-read all data from disk now. Ignore any cached content. The corpus is large —
process it with scripts (ripgrep / bash / python), never by eyeballing. Report concrete numbers
where you can.

## Corpus
{{CORPUS_PATHS_AND_EXTRACTION_RULES}}

## Optional seed (may be empty)
{{ORIGINAL_CLAIM}}
<!-- If a seed claim is given, treat it only as a starting direction; you may diverge. -->

## Your task
1. Mechanically survey the corpus (enumerate, count, sample) to observe patterns.
2. Propose **2–4 competing candidate hypotheses** about naming / structure / behavior / trend
   (whatever the corpus supports). For EACH candidate:
   - **H_n**: one falsifiable sentence (something a count/rate/ratio could refute).
   - **Observations**: 2–3 concrete things you saw that suggest it (cite names / lines / numbers).
   - **Alternative explanation**: a different reading of the same observations.
   - **Discriminating measure**: what the deductive role could measure to tell this candidate
     apart from the others.
3. Note which candidates are mutually exclusive vs compatible.

Make at least one candidate **tension-bearing** (likely to be only partially true), so the loop
has something real to refine. No sycophancy, no safe truisms.

## Response format

\`\`\`markdown
### Candidate H1
- H1: ...
- observations: ... / ... / ...
- alternative: ...
- discriminating measure: ...

### Candidate H2
...

### Notes
- mutually exclusive: H1 vs H3 ; compatible: H1 + H2
\`\`\`

---
status: stop
---
```

## After abduction (handled by Claude in Phase 0b)

- Claude (or the user via `AskUserQuestion`) selects ONE candidate as the confirmed hypothesis **H**.
- Selection criteria: falsifiability, discriminability, and how much it would teach if wrong.
- The confirmed H — **and nothing from this abduction thread's rationale/candidates** — is what
  gets passed to the induction role on a *fresh* thread (independence guard).

## Quality bar

- A single candidate is **not** acceptable — it invites premature fixation. Demand competition.
- Every candidate must be refutable by a measure over the corpus.
- If the corpus cannot be read, say so rather than inventing patterns.
