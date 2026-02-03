# Devil's Advocate Evaluation Criteria

This document defines the criteria for Red Team verdicts in Devil's Advocate reviews.

## Verdict Types

### APPROVE

**Definition**: The proposal is sound and can proceed as designed.

**Criteria**:
- No critical or high-severity issues remain unaddressed
- All major concerns have been adequately addressed
- Implementation is feasible within stated constraints
- Benefits clearly outweigh remaining risks
- Alternative approaches do not offer significant advantages

**Indicators**:
- Blue Team has provided satisfactory responses to all major concerns
- Remaining issues are low-severity or out of scope
- The proposal demonstrates awareness of edge cases
- Risk mitigation strategies are adequate

**Example Verdict Statement**:
```markdown
**Decision:** APPROVE

**Reasoning:**
The proposal to add API caching is well-designed. Blue Team adequately addressed
the cache invalidation concern by switching to cache-aside pattern with explicit
invalidation. The Redis SPOF concern is mitigated by the fallback mechanism.

**Remaining Risks:**
- Cache stampede during cold start (Low - acceptable)
- Memory pressure under high cardinality (Low - monitoring in place)
```

---

### CONDITIONAL

**Definition**: The proposal can proceed but requires specific conditions to be met.

**Criteria**:
- No critical issues remain
- Some high or medium-severity concerns remain but are manageable
- Implementation is feasible with modifications
- Benefits justify accepting controlled risks
- Specific conditions can be defined and verified

**Indicators**:
- Blue Team addressed most concerns but gaps remain
- Outstanding issues have clear remediation paths
- Conditions are actionable and verifiable
- Risk is acceptable if conditions are met

**Example Verdict Statement**:
```markdown
**Decision:** CONDITIONAL

**Reasoning:**
The microservices migration proposal is viable but requires additional safeguards.
The service decomposition strategy is sound, but inter-service communication
patterns need clarification before implementation.

**Conditions:**
1. Define explicit service contracts using OpenAPI before implementation
2. Implement circuit breakers for all cross-service calls
3. Establish observability baseline (distributed tracing, centralized logging)

**Remaining Risks:**
- Data consistency during transition (Medium - addressed by condition #1)
- Operational complexity increase (Medium - addressed by condition #3)
```

---

### REJECT

**Definition**: The proposal has fundamental issues requiring redesign.

**Criteria**:
- Critical flaws that fundamentally undermine the proposal
- Major risks that cannot be adequately mitigated
- Alternative approaches are clearly superior
- Implementation would cause significant harm
- Blue Team responses do not adequately address core issues

**Indicators**:
- Core assumptions of the proposal are flawed
- Blue Team cannot provide satisfactory responses to critical concerns
- The cure is worse than the disease
- Proposal introduces more problems than it solves

**Example Verdict Statement**:
```markdown
**Decision:** REJECT

**Reasoning:**
The proposal to implement custom encryption cannot be approved. Using a
custom-built encryption algorithm introduces unacceptable security risks.
Industry-standard libraries exist that solve this problem more safely.

**Critical Issues:**
1. Custom cryptography is a well-known anti-pattern
2. The proposed algorithm has not undergone security review
3. Standard alternatives (libsodium, OpenSSL) are readily available

**Recommendation:**
Redesign using established cryptographic libraries. The underlying requirements
(data protection at rest) are valid but must be implemented using proven
solutions.
```

---

## Severity Assessment Guidelines

### Critical Severity

Issues that **must** be addressed before any approval is possible.

**Characteristics**:
- Security vulnerabilities (data exposure, injection, authentication bypass)
- Data loss or corruption risks
- Legal/compliance violations
- Fundamental architectural flaws
- Inability to meet core requirements

**Questions to Ask**:
- Could this lead to a security breach?
- Could users lose data?
- Does this violate regulations or policies?
- Is the core approach fundamentally sound?

### High Severity

Issues that **should** be addressed but don't necessarily block approval.

**Characteristics**:
- Significant performance impacts
- Missing error handling for common cases
- Incomplete implementation of requirements
- Scalability limitations under expected load
- Significant maintainability concerns

**Questions to Ask**:
- Will this work under expected conditions?
- Can developers maintain this effectively?
- Are common failure modes handled?
- Does this scale to expected usage?

### Medium Severity

Issues worth noting and addressing but not blocking.

**Characteristics**:
- Edge cases not handled
- Documentation gaps
- Code quality concerns
- Minor performance inefficiencies
- Non-critical feature gaps

**Questions to Ask**:
- Is this a nice-to-have or a need-to-have?
- Can this be addressed in a follow-up?
- Does this affect day-to-day usage?
- Is the impact limited in scope?

### Low Severity

Minor improvements or observations.

**Characteristics**:
- Style or naming suggestions
- Optional optimizations
- Alternative approaches to consider
- Future enhancement ideas
- Best practice recommendations

**Questions to Ask**:
- Is this subjective or objective?
- Would addressing this significantly improve the proposal?
- Is this within the current scope?
- Is the effort worth the benefit?

---

## Constructive Critique Principles

### Be Specific
Bad: "The security is weak."
Good: "The password validation allows passwords under 8 characters, which doesn't meet OWASP guidelines."

### Provide Alternatives
Bad: "This approach won't scale."
Good: "This O(n²) algorithm won't scale beyond 10k items. Consider using a hash map for O(1) lookups."

### Prioritize Appropriately
Focus discussion on high-impact issues rather than bikeshedding on low-impact details.

### Acknowledge Good Aspects
Recognize what the proposal does well before diving into critiques.

### Stay Objective
Base critiques on technical merit, not personal preferences (unless preferences align with project standards).

---

## Red Team Ethics

The goal of Devil's Advocate is to **improve proposals**, not to block them unnecessarily.

### Do
- Seek to understand the proposal's intent
- Provide actionable feedback
- Acknowledge when concerns are adequately addressed
- Focus on substantive issues
- Respect the effort put into the proposal

### Don't
- Block for the sake of blocking
- Move goalposts after concerns are addressed
- Require perfection when good-enough suffices
- Conflate preferences with requirements
- Dismiss proposals without engagement
