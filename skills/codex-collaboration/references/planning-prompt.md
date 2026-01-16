# Planning Prompt Template

Use this template when requesting a plan from Codex. The protocol header is included to enable structured communication.

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

You are collaborating with Claude Code on the following task. Your role is to create a detailed implementation plan that Claude Code will execute.

## Task Description
{task_description}

## Context
{relevant_context}

## Current Codebase State
{files_summary}

## Your Role
Create a comprehensive implementation plan. Do NOT implement the changes yourself - Claude Code will handle implementation.

## Required Output

Respond using the protocol above. Use type=task_card with:

```yaml
type: task_card
id: plan-{unique_id}
status: ok
next_action: stop  # or 'continue' if you have follow-up questions
body:
  title: "Brief title of the plan"
  context: "Summary of the situation"
  requirements:
    - "Requirement 1"
    - "Requirement 2"
  acceptance_criteria:
    - "Criterion 1"
    - "Criterion 2"
  proposed_steps:
    - step: 1
      action: "create|modify|delete"
      file: "path/to/file"
      description: "What to do"
    - step: 2
      action: "..."
      file: "..."
      description: "..."
  risks:
    - "Risk 1"
    - "Risk 2"
  test_considerations:
    - "What should be tested"
```

If you have questions before creating the plan, use type=action_request with next_action=continue.

Provide your response now.
```

## Usage Notes

Replace placeholders:
- `{task_description}`: User's original request
- `{relevant_context}`: Code snippets, architecture info
- `{files_summary}`: List of relevant files and their purposes
- `{unique_id}`: Generate a short unique identifier

Keep context focused - include only what's needed for planning.

## Parsing Response

Claude Code should:
1. Parse the YAML response
2. Validate required fields exist
3. Be lenient with extra fields
4. Fall back to unstructured parsing if YAML fails

## Multi-turn Exchange

If Codex responds with `next_action: continue` or `type: action_request`:
1. Claude processes the response and formulates an answer
2. Claude sends a follow-up message with conversation history
3. Exchange continues until `next_action: stop` or max iterations reached

History management:
- Keep latest 2 rounds in full
- Summarize earlier rounds (key decisions, unresolved questions, constraints)
