# Review Prompt Template

Use this template when requesting a code review from Codex. The protocol header is included to enable structured communication.

## Template

```
## Protocol (codex-collab/v1)
format: yaml
rules:
  - respond with exactly one top-level YAML mapping
  - include required fields: type, id, status, body
  - if unsure or blocked, use type=action_request with clarifying questions
  - include next_action (continue|stop) to signal exchange flow
types:
  task_card: {body: title, context, requirements, acceptance_criteria, proposed_steps, risks, test_considerations}
  result_report: {body: summary, changes, tests, risks, checks}
  action_request: {body: question, options, expected_response}
  review: {body: verdict, summary, findings, suggestions}
status: [ok, partial, blocked]
verdict: [pass, conditional, fail]
severity: [low, medium, high]
next_action: [continue, stop]

---

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

## Required Output

Respond using the protocol above. Use type=review with:

```yaml
type: review
id: review-{unique_id}
status: ok
next_action: stop  # use 'continue' if follow-up review needed
body:
  verdict: "pass|conditional|fail"
  summary: "One paragraph summary of the review"
  findings:
    - severity: "low|medium|high"
      location: "file:line"
      message: "What's wrong"
      suggestion: "How to fix"
  suggestions:
    - "Improvement 1"
    - "Improvement 2"
```

Note: Additional fields (alignment, code_quality, security) are accepted but not required.

If you need more information before reviewing, use type=action_request with next_action=continue.

For follow-up reviews after fixes:
- Use next_action=continue if you want to review additional changes
- Use next_action=stop when review is complete

Provide your review now.
```

## Usage Notes

Replace placeholders:
- `{original_task}`: User's original request
- `{original_plan}`: Plan from planning phase
- `{files_changed}`: List of files modified
- `{diff_summary}`: Summary of actual changes made
- `{unique_id}`: Generate a short unique identifier

For large diffs, provide a summary rather than full diff to stay within context limits.

## Parsing Response

Claude Code should:
1. Parse the YAML response
2. Check verdict field for pass/conditional/fail
3. Extract findings for actionable items
4. Be lenient with extra fields
5. Fall back to unstructured parsing if YAML fails
