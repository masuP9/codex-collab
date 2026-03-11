# Plan Review Prompt Template

This template is used to generate plan review requests for Codex during collaborative planning.

## Template Variables

| Variable | Description |
|----------|-------------|
| `${LANG_DIRECTIVE}` | Language directive (empty for English) |
| `${TASK_DESCRIPTION}` | The original task/idea from the user |
| `${PLAN_DRAFT}` | The current plan draft |
| `${CURRENT_ITERATION}` | Current iteration number |
| `${MAX_ITERATIONS}` | Maximum iterations allowed |
| `${PREVIOUS_FEEDBACK}` | Previous review feedback (empty for first iteration) |
| `${SNAPSHOT_HISTORY}` | Summary snapshots from previous iterations |

## Prompt Template

```markdown
${LANG_DIRECTIVE}You are a plan reviewer. Your job is to evaluate an implementation plan and provide structured feedback.

## Context

A plan has been drafted for the following task:

${TASK_DESCRIPTION}

## Plan to Review

${PLAN_DRAFT}

## Previous Feedback History

${SNAPSHOT_HISTORY}

## Review Instructions

Evaluate the plan against these criteria:

1. **Completeness**: Does the WBS cover all necessary changes? Are there missing files or steps?
2. **Correctness**: Are the proposed changes technically sound? Any logical errors?
3. **Risk coverage**: Are significant risks identified? Are mitigations adequate?
4. **Actionability**: Are implementation steps clear enough to follow without ambiguity?
5. **Scope**: Is the scope appropriate? Too broad or too narrow?
6. **Verification**: Are test/verification methods sufficient to catch regressions?

Iteration ${CURRENT_ITERATION} of ${MAX_ITERATIONS}.

## Response Format

\`\`\`markdown
### Plan Review (Iteration ${CURRENT_ITERATION})

#### Quality Assessment
**quality: [good / needs-improvement / major-revision]**

#### Section Feedback

**Purpose**: [OK / feedback]
**Scope Exclusions**: [OK / feedback]
**Work Breakdown**: [OK / feedback]
**Implementation Steps**: [OK / feedback]
**Risk Assessment**: [OK / feedback]
**Verification Methods**: [OK / feedback]
**Completion Criteria**: [OK / feedback]

#### Key Issues
1. **[Severity: High/Medium/Low]** [Issue description]
   - Problem: [What's wrong]
   - Suggestion: [How to fix]

2. ...

#### Positive Aspects
- [What the plan does well]

#### Summary Snapshot
**Decisions confirmed:**
- [Items that are settled and should not be revisited]

**Open items:**
- [Items that still need resolution]

**Rejected ideas:**
- [Approaches considered and dismissed, with reason]
\`\`\`

---
quality: [good/needs-improvement/major-revision]
---
```

## Quality Assessment Criteria

### good

The plan is ready for implementation.

**Criteria**:
- All WBS entries are correct and complete
- Implementation steps are clear and ordered
- Risks are adequately identified and mitigated
- Verification methods are sufficient
- Completion criteria are measurable
- No high-severity issues remain

### needs-improvement

The plan has issues that can be fixed with targeted revisions.

**Criteria**:
- Some WBS entries are missing or incorrect
- Implementation steps need clarification
- Risk coverage has gaps
- Minor structural or completeness issues
- No fundamental design problems

### major-revision

The plan has fundamental problems requiring significant rework.

**Criteria**:
- Core approach is flawed or incomplete
- WBS misses critical components
- Risks are severely underestimated
- Scope is inappropriate (too broad/narrow)
- Plan would lead to failed implementation

## Summary Snapshot Purpose

Each review iteration produces a summary snapshot to:
- **Prevent context degradation** across iterations
- **Track decisions** so settled items aren't revisited
- **Record rejected alternatives** to avoid circular discussions
- **Identify open items** for the next iteration to focus on

The snapshot is prepended to `${SNAPSHOT_HISTORY}` for subsequent iterations.

## Guidelines for Effective Review

### Do
- Be specific about what's missing or wrong
- Provide actionable suggestions, not vague criticism
- Acknowledge good aspects of the plan
- Focus on high-impact issues first
- Consider the plan from an implementer's perspective

### Don't
- Require perfection on first iteration
- Suggest scope expansion beyond the original task
- Focus on formatting over substance
- Repeat feedback that was already addressed
- Propose alternative architectures unless the current one is fundamentally flawed
