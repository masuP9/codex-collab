---
name: Strong Inference
description: This skill should be used when the user wants to "investigate a bug", "debug an issue", "figure out why something is happening", "find the root cause", "troubleshoot", "強い推論で調査", "仮説を立てて検証", "原因を特定", "バグの原因調査", "なぜ動かないか調べて", "問題を切り分け", "原因不明", "デバッグ", or mentions systematic hypothesis-driven debugging. NOTE: Use this for investigating UNKNOWN causes, not for validating design proposals (use devils-advocate for that).
---

# Strong Inference Skill

Apply the "Strong Inference" methodology to investigate problems systematically through competing hypotheses and decisive experiments.

## Overview

Strong Inference is a scientific method that accelerates problem-solving by:
1. Generating multiple **competing** hypotheses
2. Designing experiments that **eliminate** hypotheses
3. Iterating until the most likely explanation remains

This skill helps developers investigate bugs, performance issues, and unexpected behaviors using a structured, hypothesis-driven approach.

**Key Feature**: In codex mode, this skill can optionally leverage Codex for hypothesis generation and review while Claude handles verification execution.

## Prerequisites

- The user has a problem, bug, or unexpected behavior to investigate
- Relevant code context is available
- For Codex collaboration mode: Codex CLI available (`codex exec`)

## Workflow Phases

### Phase 1: Problem Definition

When the user presents a problem:

1. **Collect information**:
   - Error messages, logs, stack traces
   - Steps to reproduce
   - Expected vs actual behavior
   - Recent changes that might be related

2. **Clarify scope**:
   - Which components are involved?
   - When did it start happening?
   - Is it reproducible consistently?

### Phase 2: Hypothesis Generation

Generate 2-4 **competing hypotheses** that are:
- **Mutually exclusive**: If H1 is true, H2 cannot be true
- **Testable**: Can be verified or eliminated with evidence
- **Specific**: Clear enough to design a decisive test

**Example hypotheses for "API returns 500 intermittently":**
```
H1: Database connection pool exhausted under load
H2: Race condition in cache update causing stale data
H3: External service timeout not handled properly
H4: Memory leak causing OOM conditions
```

### Phase 3: Verification Design

For each hypothesis, design a "killer experiment" that:
- Can **eliminate** the hypothesis if the result is negative
- Requires **minimal effort** for maximum information gain
- Is **safe** to execute (no production impact)

**Prioritize experiments by:**
1. Ease of execution (quick wins first)
2. Discriminating power (eliminates multiple hypotheses)
3. Risk level (non-destructive first)

### Phase 4: Verification Execution

Execute verifications in priority order:
- Code inspection (reading files, checking logic)
- Log analysis (searching for patterns)
- Test execution (running specific tests)
- Instrumentation (adding debug output)

**Safety guards:**
- Confirm before any file modifications
- Set timeouts for long-running operations
- Log all executed commands

### Phase 5: Analysis and Iteration

After each verification:

1. **Record evidence**: What was observed?
2. **Update hypothesis status**:
   - `[X]` Eliminated (evidence contradicts)
   - `[?]` Pending (not yet tested)
   - `[!]` Supported (evidence aligns)
3. **Refine remaining hypotheses** based on new information
4. **Generate new hypotheses** if all were eliminated

### Phase 6: Conclusion

When one hypothesis has strong supporting evidence:

1. **Summarize findings**: Evidence trail and reasoning
2. **Propose solution**: Based on confirmed hypothesis
3. **Suggest prevention**: How to avoid similar issues

## Role Distribution

| Mode | Hypothesis Gen | Verification Design | Execution | Review |
|------|----------------|---------------------|-----------|--------|
| `codex` | Codex | Claude | Claude | Codex |
| `claude-only` | Claude | Claude | Claude | Claude |

- **Default mode**: `codex` (when Codex CLI available)
- **Fallback**: `claude-only` (automatic when Codex unavailable)

## Hypothesis Tree File

Investigation state is persisted to `tmp/strong-inference/<task-id>.md`:

```yaml
---
schema: strong-inference/v1
task_id: abc123
created: 2026-02-02T12:00:00Z
problem: "API returns 500 intermittently"
mode: codex
---

# Investigation: API returns 500 intermittently

## Hypotheses

### H1: Database connection pool exhausted
- Status: [X] Eliminated
- Evidence: Connection count stable at 5/20 during error window
- Verified: 2026-02-02T12:15:00Z

### H2: Race condition in cache update
- Status: [?] Pending
- Test: Add mutex logging to CacheManager.update()
- Priority: High (matches timing pattern)

### H3: External service timeout
- Status: [!] Supported
- Evidence: Errors correlate with ExternalAPI latency spikes
- Next: Verify timeout handling in ApiClient.fetch()

## Verification Log

| Time | Action | Result |
|------|--------|--------|
| 12:05 | Read db/pool.go | Found pool size config |
| 12:10 | Check connection metrics | Stable at 5/20 |
| 12:15 | Eliminated H1 | Evidence contradicts |
```

## Safety Guards

Before executing verification commands:
- **Confirm destructive operations**: File changes, test execution
- **Set timeout**: Default 60 seconds per operation
- **Log all commands**: Record in verification log

**Stop conditions:**
- All hypotheses eliminated (request new hypotheses)
- `max_iterations` reached (default: 10)
- User requests stop

## Output Format

### Progress Display

```
Strong Inference Investigation
==============================
Problem: API returns 500 error intermittently

Hypotheses:
  [X] H1: Database connection pool exhausted
      Evidence: Connection count normal (eliminated)

  [!] H2: Race condition in cache update
      Evidence: Timing matches error pattern (supported)

  [?] H3: External service timeout
      Evidence: Pending verification

Current: Designing test for H2
```

### Completion Report

```
Investigation Complete
======================
Problem: API returns 500 error intermittently

Root Cause: Race condition in CacheManager.update()
Confidence: High (3 supporting evidence points)

Evidence Trail:
1. Errors occur only during cache refresh window
2. Adding mutex eliminated the error
3. Race condition visible in thread dump

Recommended Fix:
- Add mutex lock in CacheManager.update() line 45
- Consider using sync.RWMutex for better concurrency

Prevention:
- Add race detector to CI pipeline
- Review other cache operations for similar patterns
```

## Invoking the Skill

Use the `/strong-inference` command:

```bash
# Basic usage - investigate a problem
/strong-inference API sometimes returns 500 errors

# With mode selection
/strong-inference --mode claude-only Why is the test flaky?

# Japanese
/strong-inference このバグの原因を調査して
```

## References

Detailed templates in `references/`:

- **`hypothesis-template.md`** - Template for Codex hypothesis generation
- **`verification-patterns.md`** - Common verification strategies
