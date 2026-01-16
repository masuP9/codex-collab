# Planning Prompt Template

Use this template when requesting a plan from Codex.

## Template

```
You are collaborating with Claude Code on the following task. Your role is to create a detailed implementation plan that Claude Code will execute.

## Task Description
{task_description}

## Context
{relevant_context}

## Current Codebase State
{files_summary}

## Your Role
Create a comprehensive implementation plan. Do NOT implement the changes yourself - Claude Code will handle implementation.

## Required Output Format

### 1. Files to Modify
List each file with:
- File path
- Type of change (create/modify/delete)
- Brief description of changes

### 2. Implementation Steps
Numbered steps in execution order:
1. [Step description]
2. [Step description]
...

### 3. Risk Assessment
- Potential issues or concerns
- Edge cases to handle
- Dependencies to verify

### 4. Test Considerations
- What should be tested
- Edge cases to cover
- Expected behavior changes

### 5. Recommendations
- Best practices to follow
- Alternative approaches considered
- Performance or security notes

Provide your plan now.
```

## Usage Notes

Replace placeholders:
- `{task_description}`: User's original request
- `{relevant_context}`: Code snippets, architecture info
- `{files_summary}`: List of relevant files and their purposes

Keep context focused - include only what's needed for planning.
