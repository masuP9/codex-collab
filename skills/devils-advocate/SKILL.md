---
name: Devil's Advocate
description: This skill should be used when the user wants to "stress-test a design", "challenge an idea", "red team a proposal", "get critical feedback", "validate a design", "review architecture", "risk assessment", "設計を検証して", "反論をもらいたい", "批判的にレビュー", "デビルズアドボケート", "ストレステスト", "弱点を指摘して", "穴を見つけて", "この設計で良いか", "リスク評価", "アーキテクチャレビュー", or mentions structured adversarial review of a proposal or design. NOTE: Use this for validating PROPOSALS and DESIGNS, not for investigating unknown bugs (use strong-inference for that).
---

# Devil's Advocate Skill

Apply the Devil's Advocate methodology to stress-test hypotheses, designs, and proposals through structured adversarial debate.

## Overview

Devil's Advocate is a critical thinking technique that improves decision quality by:
1. Systematically challenging assumptions and proposals
2. Identifying weaknesses before implementation
3. Refining ideas through structured debate
4. Reaching more robust conclusions

This skill helps developers validate designs, proposals, and decisions using a structured Blue Team (propose/defend) vs Red Team (critique/challenge) approach.

**Key Feature**: In codex mode, this skill leverages Codex as the Red Team critic while Claude serves as the Blue Team advocate.

## Comparison with Strong Inference

| Aspect | Strong Inference | Devil's Advocate |
|--------|------------------|------------------|
| Purpose | Verify hypothesis through experiments | Stress-test proposal through debate |
| Method | Competing hypotheses + decisive experiments | Adversarial critique + iterative refinement |
| Output | Root cause with evidence trail | Refined proposal with verdict |
| Best For | Debugging, investigation, unknown causes | Design review, decision validation, risk assessment |

## Prerequisites

- The user has a proposal, design, or hypothesis to validate
- Relevant context is available (code, docs, requirements)
- For Codex collaboration mode: Codex CLI available (`codex exec`)

## Workflow Phases

### Phase 1: Proposal Definition

When the user presents a proposal:

1. **Collect information**:
   - Design documents or specifications
   - Related code and architecture
   - Requirements and constraints
   - Context on why this approach was chosen

2. **Clarify scope**:
   - What specific aspects need validation?
   - What are the known constraints?
   - What alternatives were considered?

### Phase 2: Blue Team Presentation (Claude)

Present and defend the proposal:
- **Clear statement** of what is being proposed
- **Rationale** for why this approach was chosen
- **Benefits** expected from implementation
- **Anticipated concerns** and planned mitigations

### Phase 3: Red Team Critique (Codex/Claude)

Challenge the proposal systematically:
- **Logical flaws** in reasoning
- **Technical risks** and implementation challenges
- **Edge cases** not considered
- **Security, scalability, maintainability** concerns
- **Alternative approaches** that might be better

Concerns are categorized by severity:
- **Critical**: Fundamental flaws that block approval
- **High**: Significant issues requiring changes
- **Medium**: Notable concerns to address
- **Low**: Minor improvements or considerations

### Phase 4: Defense and Refinement (Claude)

Respond to Red Team critique:
- **Address** each concern with reasoning or changes
- **Acknowledge** valid points that require modification
- **Present** refined proposal incorporating feedback
- **Explain** why certain concerns may not apply

### Phase 5: Re-evaluation and Iteration

Red Team reassesses:
- **Acknowledge** adequately addressed concerns
- **Identify** remaining or new issues
- **Prioritize** the most critical unresolved items
- **Continue** until max rounds or consensus

### Phase 6: Final Verdict

After all rounds, Red Team provides:

**APPROVE**: No critical issues, proposal is sound
- Implementation can proceed as designed
- Benefits clearly outweigh remaining risks

**CONDITIONAL**: Proceed with specific conditions
- Implementation can proceed with changes
- Specific conditions must be met
- Follow-up actions may be required

**REJECT**: Fundamental issues require redesign
- Critical flaws undermine the proposal
- Alternative approaches should be considered
- Re-submit after significant revision

## Role Distribution

| Mode | Blue Team | Red Team |
|------|-----------|----------|
| `codex` | Claude | Codex |
| `claude-only` | Claude | Claude |

- **Default mode**: `codex` (when Codex CLI available)
- **Fallback**: `claude-only` (automatic when Codex unavailable)

## Debate State File

Debate state is persisted to `tmp/devils-advocate/<task-id>.md`:

```yaml
---
schema: devils-advocate/v1
task_id: abc123
created: 2026-02-03T12:00:00Z
proposal: "Add caching layer to API responses"
mode: codex
round: 2
max_rounds: 3
status: in_progress
verdict: pending
---

# Red Team Review: Add caching layer to API responses

## Overview

**Proposal:** Add caching layer to API responses
**Mode:** codex
**Max Rounds:** 3

## Debate Log

### Round 1

#### Blue Team (Claude)

**Position:**
We should add a Redis-based caching layer to reduce database load...

**Key Points:**
1. 80% of requests are read-only and cacheable
2. Expected 60% reduction in DB queries
3. TTL-based invalidation for simplicity

#### Red Team (Codex)

**Key Concerns:**
1. **[Severity: High]** Cache invalidation complexity
   - Issue: Write operations may leave stale data
   - Impact: Users see outdated information
   - Suggestion: Implement cache-aside with explicit invalidation

2. **[Severity: Medium]** Redis as single point of failure
   - Issue: Redis downtime affects entire API
   - Impact: Service degradation
   - Suggestion: Add fallback to direct DB queries

### Round 2

...
```

## Safety Guards

The debate process includes:
- **Fair critique**: Red Team should be constructive, not obstructive
- **Severity levels**: Concerns are prioritized appropriately
- **Iteration limits**: Default 3 rounds prevents endless debate
- **Evidence-based**: Critique should cite specific concerns, not vague objections

## Output Format

### Progress Display

```
Devil's Advocate Review
=======================
Proposal: Add caching layer to API responses

Round 2 of 3
Status: Blue Team defending

Current concerns:
  [!] High: Cache invalidation complexity (Addressed)
  [?] Medium: Redis SPOF (Pending response)
  [X] Low: Documentation needs (Addressed)
```

### Completion Report

```
Devil's Advocate Review Complete
================================
Proposal: Add caching layer to API responses

Verdict: CONDITIONAL

Summary:
The caching proposal is sound with modifications. Blue Team
adequately addressed invalidation concerns by switching to
cache-aside pattern. Redis SPOF concern requires fallback.

Conditions:
1. Implement fallback to direct DB queries when Redis unavailable
2. Add cache hit/miss metrics for monitoring

Remaining Risks:
- Cache stampede during cold start (Low)
- Memory pressure under high cardinality (Low)

Recommendations:
- Proceed with implementation
- Address conditions before production deployment
- Monitor closely during initial rollout
```

## Invoking the Skill

Use the `/devils-advocate` command:

```bash
# Basic usage - stress-test a design
/devils-advocate Add a caching layer to reduce database load

# With mode selection
/devils-advocate --mode claude-only Should we migrate to microservices?

# With custom rounds
/devils-advocate --max-rounds 5 This authentication redesign

# Japanese
/devils-advocate この認証設計を批判的にレビューして
```

## References

Detailed templates in `references/`:

- **`critique-prompt.md`** - Template for Red Team critique generation
- **`evaluation-criteria.md`** - Detailed verdict criteria
