# Hypothesis Generation Template

This template is used when requesting hypothesis generation from Codex in `codex` mode.

## Prompt Template

```markdown
You are helping investigate a problem using Strong Inference methodology.

**IMPORTANT**: If you reference any files, always re-read them from disk even if you have read them before in this session. Ignore any cached content from earlier in this conversation.

## Problem

{{PROBLEM_DESCRIPTION}}

## Context

{{CONTEXT}}

### Error Details
{{ERROR_DETAILS}}

### Related Files
{{RELATED_FILES}}

### Recent Changes
{{RECENT_CHANGES}}

## Strong Inference Principles

1. **Generate competing hypotheses**: Multiple explanations that could account for the observations
2. **Hypotheses must be mutually exclusive**: If H1 is true, it reduces the likelihood of H2
3. **Design for elimination**: Focus on experiments that can definitively rule out hypotheses
4. **Minimal experiments**: Choose tests that provide maximum information with minimal effort

## Task

Generate 2-4 **competing hypotheses** that could explain this problem.

### Requirements

1. **Mutually exclusive**: If one hypothesis is true, the others become less likely
2. **Testable**: Each can be verified or eliminated with specific, concrete evidence
3. **Specific**: Clear enough to design a decisive experiment
4. **Prioritized**: Order by likelihood based on available evidence

### For Each Hypothesis

Provide:
- **Statement**: A clear, specific statement of the hypothesis
- **Reasoning**: Why this could be the cause based on the context
- **Elimination test**: What evidence would definitively prove this wrong
- **Verification approach**: How to test this hypothesis

## Response Format

Respond with hypotheses in this format:

```markdown
### H1: [Most likely hypothesis - brief title]

**Statement:** [Clear statement of what might be causing the problem]

**Reasoning:**
- [Why this is plausible based on evidence]
- [What patterns support this hypothesis]

**Elimination test:**
- If we observe [X], this hypothesis is eliminated
- Specifically: [concrete test]

**Verification approach:**
1. [First step to verify]
2. [Second step if needed]

**Priority:** High | Medium | Low
**Effort:** Low | Medium | High

---

### H2: [Second most likely hypothesis]

**Statement:** [...]

**Reasoning:**
- [...]

**Elimination test:**
- [...]

**Verification approach:**
1. [...]

**Priority:** [...]
**Effort:** [...]

---
```

## Example

For problem: "API returns 500 error intermittently"

```markdown
### H1: Database connection pool exhaustion

**Statement:** The database connection pool is being exhausted under load, causing queries to timeout and trigger 500 errors.

**Reasoning:**
- Errors occur during peak traffic times
- Error logs show database timeout messages
- Pool size may be undersized for current load

**Elimination test:**
- If connection pool metrics show stable, low utilization during errors, this is eliminated
- Check: Pool connections should exceed 80% capacity when errors occur

**Verification approach:**
1. Check database connection pool metrics during error window
2. Compare pool size configuration vs peak connections
3. Correlate error timestamps with pool utilization

**Priority:** High
**Effort:** Low

---

### H2: Race condition in cache invalidation

**Statement:** A race condition in the cache invalidation logic causes stale data to be served, triggering validation errors that result in 500 responses.

**Reasoning:**
- Errors occur after write operations
- Multiple instances may invalidate cache simultaneously
- No distributed locking on cache operations

**Elimination test:**
- If errors occur without any preceding write operations, this is eliminated
- If single-instance deployment shows same errors, race condition is unlikely

**Verification approach:**
1. Add logging around cache operations with timestamps
2. Check if errors correlate with cache invalidation events
3. Review cache invalidation code for race conditions

**Priority:** Medium
**Effort:** Medium
```

---
status: stop
---
```

## Usage Notes

1. **Replace placeholders** with actual problem context before sending to Codex
2. **Include all relevant context** - Codex cannot access files directly
3. **Keep hypotheses focused** - 2-4 is the ideal range
4. **Prioritization matters** - Test highest-priority hypotheses first

## Variables

| Variable | Description | Source |
|----------|-------------|--------|
| `{{PROBLEM_DESCRIPTION}}` | User's original problem statement | Step 1 |
| `{{CONTEXT}}` | Summary of gathered context | Step 2 |
| `{{ERROR_DETAILS}}` | Error messages, stack traces | Step 2 |
| `{{RELATED_FILES}}` | List of relevant files with descriptions | Step 2 |
| `{{RECENT_CHANGES}}` | Git history or change summary | Step 2 |
