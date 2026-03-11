---
name: Collaborative Planning
description: This skill should be used when the user wants to "plan with Codex", "create a plan", "draft implementation plan", "help me plan", "plan before implementing", "refine a plan", "review my plan idea", "Codexと計画を立てる", "実装計画を作成", "計画を立てたい", "計画を一緒に考えて", "実装方針を相談", "Codexと設計を練る", "計画だけ作りたい", "実装前に計画を立てたい", "計画をレビューしてほしい", or mentions creating/refining an implementation plan as the deliverable without proceeding to implementation. NOTE: This is for PLAN-ONLY workflows that produce a plan document as the deliverable. Do NOT use when the user wants implementation (use codex-collab instead). Do NOT use for adversarial design critique (use devils-advocate instead). Do NOT use for debugging (use strong-inference instead).
---

# Collaborative Planning Skill

Create and refine implementation plans through collaborative iteration between Claude and Codex. **Plans only — no implementation.**

## Overview

Collaborative Planning produces a polished implementation plan by:
1. Claude collects codebase context and drafts a plan based on the user's idea
2. Codex reviews the plan and provides structured feedback
3. Claude refines the plan based on feedback
4. Iterate until plan quality is sufficient

**Key constraint**: This skill NEVER starts implementation. The deliverable is always a plan document.

## Comparison with Other Skills

| Aspect | collab-planning | codex-collab | devils-advocate |
|--------|-----------------|--------------|-----------------|
| Purpose | Create/refine plans only | Plan + implement + review | Stress-test a design |
| Implementation | **Never** | Yes (Claude or Codex) | No |
| Deliverable | Plan document (fixed template) | Implemented code | Verdict (APPROVE/CONDITIONAL/REJECT) |
| Claude's role | Context collection + draft | Implementation or review | Blue Team advocate |
| Codex's role | Plan review + improvement | Planning or implementation | Red Team critic |
| Use case | Pre-implementation planning | End-to-end task execution | Design validation |

## Prerequisites

- The user has an idea, task, or feature to plan
- Relevant codebase context is available
- For Codex collaboration: Codex CLI available (`codex exec`) or MCP configured

## Workflow Phases

### Phase 1: Context Collection

Claude gathers information:
1. Read relevant files and architecture
2. Identify affected components
3. Understand constraints and dependencies
4. Clarify scope with user if needed

### Phase 2: Draft Plan

Claude creates an initial plan using the fixed template:
- Purpose, scope exclusions, work breakdown
- Implementation steps, risks, verification, completion criteria

### Phase 3: Codex Review

Codex reviews the plan and provides:
- Quality assessment: `good` / `needs-improvement` / `major-revision`
- Specific feedback on each section
- Missing considerations or risks
- Summary snapshot (decisions, open items, rejected ideas)

### Phase 4: Iteration

Based on quality assessment:
- `good` → Finalize and present to user
- `needs-improvement` → Claude refines, re-submit to Codex
- `major-revision` → Ask user for direction, then re-draft or conclude

### Phase 5: Final Output

Present the polished plan in the fixed template format.

## Settings (`.claude/codex-collab.local.md`)

```yaml
collab_planning:
  max_iterations: 3          # Review improvement cycle limit
  user_confirm: on_important  # never | always | on_important
```

Existing settings (`model`, `sandbox`, `language`) are also respected.

## Invoking the Skill

Use the `/collab-planning` command:

```bash
# Basic usage
/collab-planning Add pagination to the user list API

# With options
/collab-planning --max-iterations 5 Refactor authentication module

# Japanese
/collab-planning ユーザーリストAPIにページネーションを追加する計画を立てたい
```

## References

Detailed templates in `references/`:

- **`plan-draft-guide.md`** - Fixed template for plan documents
- **`plan-review-prompt.md`** - Template for Codex review requests
