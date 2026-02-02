# Verification Patterns

Common verification strategies for Strong Inference investigations.

## Pattern Categories

### 1. Code Inspection

Static analysis of source code to verify or eliminate hypotheses.

#### Pattern: Logic Flow Analysis
```yaml
name: Logic Flow Analysis
description: Trace code execution path to verify expected behavior
when_to_use:
  - Hypothesis involves incorrect control flow
  - "If X then Y should happen" type questions
  - Off-by-one or boundary condition issues
steps:
  - Identify entry point for the problematic operation
  - Trace execution path through conditionals and loops
  - Check boundary conditions and edge cases
  - Verify return values and error handling
tools: [Read, Grep]
effort: Low
```

#### Pattern: Dependency Check
```yaml
name: Dependency Check
description: Verify external dependencies and their configurations
when_to_use:
  - Hypothesis involves third-party library behavior
  - Version mismatch suspected
  - Configuration issues
steps:
  - Check package.json/go.mod/requirements.txt for versions
  - Compare with known working versions
  - Review library changelog for breaking changes
  - Check configuration files for correct settings
tools: [Read, Grep, Bash]
effort: Low
```

#### Pattern: Concurrency Analysis
```yaml
name: Concurrency Analysis
description: Check for race conditions and synchronization issues
when_to_use:
  - Intermittent failures
  - Multi-threaded or async code
  - Shared state modifications
steps:
  - Identify shared state (global vars, caches, databases)
  - Check for proper locking/synchronization
  - Look for read-modify-write patterns without locks
  - Verify async operations have proper await/sync
tools: [Read, Grep]
effort: Medium
```

### 2. Log Analysis

Searching through logs to find patterns and evidence.

#### Pattern: Error Correlation
```yaml
name: Error Correlation
description: Find patterns in error occurrences
when_to_use:
  - Intermittent errors with unclear trigger
  - Time-based issues suspected
  - Load-related problems
steps:
  - Extract error timestamps
  - Correlate with other events (deployments, traffic spikes)
  - Check for periodic patterns
  - Compare with success cases during same period
tools: [Grep, Bash]
effort: Low
example: |
  # Find errors in last hour and correlate with requests
  grep "ERROR" app.log | grep "$(date -d '1 hour ago' +%Y-%m-%d)"
  grep "request_id=XYZ" app.log | sort -t'T' -k2
```

#### Pattern: State Transition Trace
```yaml
name: State Transition Trace
description: Track state changes leading to error
when_to_use:
  - State corruption suspected
  - Multi-step operations failing
  - Data consistency issues
steps:
  - Find the failing operation's request/transaction ID
  - Trace all state changes for that ID
  - Identify where state diverged from expected
  - Check for missing or out-of-order operations
tools: [Grep, Read]
effort: Medium
```

### 3. Test Execution

Running tests to verify hypotheses.

#### Pattern: Isolation Test
```yaml
name: Isolation Test
description: Run specific test to confirm hypothesis
when_to_use:
  - Hypothesis can be verified by existing test
  - Unit test for specific component exists
  - Integration test covers the scenario
steps:
  - Identify relevant test(s) for the hypothesis
  - Run test in isolation
  - Check test output for expected/unexpected behavior
  - If test passes but bug exists, hypothesis may be wrong
tools: [Bash]
effort: Low
safety: Confirm before running
example: |
  # Run specific test
  go test -v -run TestCacheInvalidation ./cache/...
  npm test -- --grep "cache invalidation"
```

#### Pattern: Reproduction Test
```yaml
name: Reproduction Test
description: Create minimal reproduction of the issue
when_to_use:
  - No existing test covers the scenario
  - Need to confirm exact conditions that trigger bug
  - Complex interaction suspected
steps:
  - Create minimal test case that should trigger the issue
  - Run test and observe behavior
  - If reproduces: hypothesis supported
  - If doesn't reproduce: refine conditions or eliminate hypothesis
tools: [Write, Bash]
effort: High
safety: Confirm test creation and execution
```

### 4. Instrumentation

Adding temporary debugging code.

#### Pattern: Debug Logging
```yaml
name: Debug Logging
description: Add temporary log statements to trace execution
when_to_use:
  - Need to observe runtime behavior
  - Existing logs insufficient
  - Timing or order of operations unclear
steps:
  - Identify key points to instrument
  - Add log statements with timestamps and context
  - Run the operation
  - Analyze log output
  - Remove instrumentation when done
tools: [Edit, Bash, Read]
effort: Medium
safety: Confirm before editing files
example: |
  // Add before suspected issue
  log.Printf("[DEBUG] cache.Update called at %v, key=%s", time.Now(), key)
```

#### Pattern: Metric Collection
```yaml
name: Metric Collection
description: Collect quantitative data about system behavior
when_to_use:
  - Performance hypothesis
  - Resource exhaustion suspected
  - Need baseline comparison
steps:
  - Identify metrics to collect (CPU, memory, connections, etc.)
  - Set up collection method
  - Run operation under investigation
  - Compare with baseline or expected values
tools: [Bash]
effort: Medium
example: |
  # Check database connections
  psql -c "SELECT count(*) FROM pg_stat_activity;"

  # Check memory usage
  ps aux | grep myapp | awk '{print $6}'
```

### 5. Configuration Review

Checking settings and environment.

#### Pattern: Environment Comparison
```yaml
name: Environment Comparison
description: Compare configurations between working and broken environments
when_to_use:
  - Works in one environment, fails in another
  - Recent deployment coincides with issue
  - Environment variable suspected
steps:
  - List all configuration sources
  - Compare values between environments
  - Check for missing or different values
  - Verify environment variable precedence
tools: [Read, Bash, Grep]
effort: Low
example: |
  # Compare env vars
  diff <(env | sort) <(ssh prod 'env | sort')

  # Check config file
  diff config/local.yaml config/production.yaml
```

#### Pattern: Version Verification
```yaml
name: Version Verification
description: Verify component versions match expectations
when_to_use:
  - Recent update may have introduced regression
  - Dependency version mismatch suspected
  - API compatibility issue
steps:
  - Check current versions of all components
  - Compare with last known working versions
  - Review changelogs for relevant changes
  - Check for breaking API changes
tools: [Bash, Read]
effort: Low
example: |
  # Check installed versions
  go list -m all | grep suspect-package
  npm ls suspect-package
```

## Choosing a Pattern

### By Hypothesis Type

| Hypothesis Type | Recommended Patterns |
|-----------------|---------------------|
| Logic error | Logic Flow Analysis, Isolation Test |
| Race condition | Concurrency Analysis, Debug Logging |
| Configuration | Environment Comparison, Configuration Review |
| Resource exhaustion | Metric Collection, Log Analysis |
| Version/compatibility | Version Verification, Dependency Check |
| Data corruption | State Transition Trace, Reproduction Test |

### By Effort Level

| Effort | Patterns |
|--------|----------|
| Low | Logic Flow Analysis, Dependency Check, Error Correlation, Isolation Test, Environment Comparison |
| Medium | Concurrency Analysis, State Transition Trace, Debug Logging, Metric Collection |
| High | Reproduction Test |

### By Safety Level

| Safety | Patterns |
|--------|----------|
| Read-only (safe) | Logic Flow Analysis, Dependency Check, Error Correlation, State Transition Trace |
| Execution required | Isolation Test, Reproduction Test, Metric Collection |
| Modification required | Debug Logging |

## Pattern Selection Workflow

```
1. Start with LOW effort, READ-ONLY patterns
   ↓
2. If inconclusive, try MEDIUM effort patterns
   ↓
3. If still inconclusive, consider HIGH effort patterns
   ↓
4. Always confirm before MODIFICATION or EXECUTION patterns
```

## Example Investigation

**Problem:** API returns 500 intermittently

**Hypotheses:**
1. Database connection pool exhaustion (High priority)
2. Race condition in cache (Medium priority)
3. External service timeout (Medium priority)

**Verification Plan:**

| Order | Hypothesis | Pattern | Effort | Safety |
|-------|------------|---------|--------|--------|
| 1 | H1 | Metric Collection | Medium | Safe |
| 2 | H1 | Error Correlation | Low | Safe |
| 3 | H2 | Concurrency Analysis | Medium | Safe |
| 4 | H3 | Log Analysis | Low | Safe |
| 5 | H2 | Debug Logging | Medium | Modify |

**Execution:**
1. Check connection pool metrics → Pool at 5/20 → Eliminates H1
2. Correlate errors with cache operations → Matches pattern → Supports H2
3. Analyze cache code for race conditions → Found unprotected write → Confirms H2
