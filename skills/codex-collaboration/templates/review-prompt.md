# Review Prompt Template

Use this template when requesting a code review from Codex.

## Template

```
You are reviewing implementation work done by Claude Code. Your role is to evaluate the changes and provide feedback.

## Original Task
{original_task}

## Original Plan
{original_plan}

## Changes Made

### Files Modified
{files_changed}

### Diff Summary
{diff_summary}

## Your Review Task

Evaluate the implementation against the original plan and provide a structured review.

## Required Output Format

### 1. Alignment Check
- Does implementation match the plan? (Yes/Partial/No)
- Any deviations? (List them)

### 2. Code Quality
- Readability: (Good/Acceptable/Poor)
- Maintainability: (Good/Acceptable/Poor)
- Issues found: (List specific problems)

### 3. Bugs and Issues
For each issue found:
- Severity: (Critical/High/Medium/Low)
- Location: (file:line)
- Description: (what's wrong)
- Suggestion: (how to fix)

### 4. Security Check
- Vulnerabilities found: (List any)
- Input validation: (Adequate/Missing)
- Sensitive data handling: (Proper/Concerning)

### 5. Improvement Suggestions
- Performance optimizations
- Better approaches
- Code style improvements

### 6. Verdict
Choose one:
- **PASS**: Implementation is acceptable, no critical issues
- **CONDITIONAL**: Acceptable with listed improvements
- **FAIL**: Critical issues must be addressed

### 7. Summary
One paragraph summary of your review.

Provide your review now.
```

## Usage Notes

Replace placeholders:
- `{original_task}`: User's original request
- `{original_plan}`: Plan from Phase 2
- `{files_changed}`: List of files modified
- `{diff_summary}`: Summary of actual changes made

For large diffs, provide a summary rather than full diff to stay within context limits.
