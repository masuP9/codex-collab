# Workflow Patterns

Alternative collaboration patterns beyond the default Review Type.

## Pattern 1: Review Type (Default)

**Flow**: Codex plans → Claude implements → Codex reviews

**Best for**:
- Feature implementation
- Refactoring tasks
- Bug fixes with clear scope

**Workflow**:
```
User Request
    ↓
Claude: Analyze task, prepare context
    ↓
Codex: Create implementation plan
    ↓
Claude: Validate plan, implement changes
    ↓
Codex: Review implementation
    ↓
Claude: Apply fixes if needed
    ↓
Complete
```

**Strengths**:
- Clear separation of concerns
- Built-in quality gate
- Leverages each AI's strengths

**Weaknesses**:
- More back-and-forth
- Slower for simple tasks

## Pattern 2: Consultation Type

**Flow**: Claude implements → Codex advises on request

**Best for**:
- Quick tasks with occasional complexity
- When Claude needs second opinion
- Debugging assistance

**Workflow**:
```
User Request
    ↓
Claude: Begin implementation
    ↓
[If uncertain] → Codex: Provide advice
    ↓
Claude: Continue implementation
    ↓
Complete
```

**When to use**:
- Task is mostly straightforward
- Specific technical questions arise
- Need architectural validation

## Pattern 3: Parallel Exploration

**Flow**: Both explore simultaneously, compare results

**Best for**:
- Uncertain solution approach
- Multiple valid solutions possible
- Learning and comparison

**Workflow**:
```
User Request
    ↓
Claude: Explore approach A
Codex: Explore approach B (simultaneously)
    ↓
Compare and synthesize
    ↓
Claude: Implement best approach
    ↓
Complete
```

**Caution**: Higher cost and complexity. Use sparingly.

## Pattern 4: Divide and Conquer

**Flow**: Split task, each handles portions

**Best for**:
- Large tasks with independent parts
- Clear boundaries between components
- Time-sensitive work

**Workflow**:
```
User Request
    ↓
Claude: Analyze and divide task
    ↓
Claude: Handle component A
Codex: Handle component B
    ↓
Claude: Integrate results
    ↓
Complete
```

**Requirements**:
- Task must be divisible
- Components must have clear interfaces
- Integration plan needed upfront

## Pattern Selection Guide

| Situation | Recommended Pattern |
|-----------|---------------------|
| Standard feature | Review Type |
| Quick fix | Consultation |
| Unknown approach | Parallel Exploration |
| Large task | Divide and Conquer |
| Critical code | Review Type (strict) |

## Switching Patterns Mid-Task

Start with default pattern. Switch if:

**To Consultation**:
- Task simpler than expected
- Only specific questions need Codex

**To Parallel**:
- Initial approach unclear
- User wants options compared

**To Divide and Conquer**:
- Task grows larger than expected
- Clear split points emerge

## Quality Gates by Pattern

### Review Type
- Plan completeness check
- Implementation review
- Verdict (Pass/Conditional/Fail)

### Consultation Type
- No formal gates
- Ad-hoc advice requests
- Final user validation

### Parallel Exploration
- Comparison criteria defined upfront
- Both approaches evaluated
- Selection justified

### Divide and Conquer
- Interface contracts defined
- Each component validated
- Integration tested

## Cost Considerations

| Pattern | Codex Calls | Context Size | Relative Cost |
|---------|-------------|--------------|---------------|
| Review | 2 (plan + review) | Medium | Base |
| Consultation | 0-N | Small each | Lower |
| Parallel | 1+ | Large | Higher |
| Divide | Varies | Large | Highest |

Optimize by:
- Choosing appropriate pattern
- Keeping context focused
- Using lighter models for simple tasks
