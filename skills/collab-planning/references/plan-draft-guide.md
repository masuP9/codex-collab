# Plan Draft Guide

This document defines the fixed template Claude uses when drafting implementation plans.

## Template

Every plan MUST follow this structure. All sections are required.

```markdown
## Plan: [Title]

### 1. Purpose
[What this change achieves. Be specific about the problem being solved and the expected outcome.]

### 2. Scope Exclusions
[What is intentionally OUT of scope for this plan. Be explicit to prevent scope creep.]

### 3. Work Breakdown (WBS)
| # | File | Action | Description |
|---|------|--------|-------------|
| 1 | path/to/file | create/modify/delete | Details of the change |

### 4. Implementation Steps (reference only — NOT executed by this skill)
1. [Ordered, concrete steps for future implementation]
2. [Each step should be actionable and unambiguous]

### 5. Risk Assessment
| Risk | Severity | Mitigation |
|------|----------|------------|
| [Risk description] | High/Medium/Low | [How to mitigate] |

### 6. Verification Methods
- [ ] [Test item or check to verify correctness]

### 7. Completion Criteria
- [ ] [Acceptance criterion that must be met]
```

## Guidelines

### Purpose Section
- State the "why" clearly — what problem exists and what improves after implementation
- Avoid vague statements like "improve performance"; be specific: "reduce API response time from 2s to 200ms"

### Scope Exclusions
- List at least one exclusion
- Helps reviewers understand boundaries
- Example: "Database migration is out of scope — handled separately"

### Work Breakdown
- List every file that will be created, modified, or deleted
- Order by dependency (files that others depend on come first)
- Use relative paths from project root

### Implementation Steps
- Ordered by execution sequence
- Each step should be completable independently where possible
- Include setup/teardown steps (migrations, config changes)
- Note: these steps are for reference only; this skill does NOT execute them

### Risk Assessment
- Include at least one risk
- Severity: High = blocks release, Medium = needs attention, Low = nice to address
- Every risk must have a mitigation strategy

### Verification Methods
- Include unit tests, integration tests, manual checks as appropriate
- Be specific: "Run `npm test -- --grep 'pagination'`" not just "run tests"

### Completion Criteria
- Measurable, binary (done or not done)
- Tied back to the Purpose section
- Example: "API returns paginated results with `next_cursor` field"
