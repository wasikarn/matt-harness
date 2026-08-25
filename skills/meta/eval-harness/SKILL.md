---
name: eval-harness
description: Eval-driven development (EDD) framework for Claude Code. Use when setting up EDD, building graders, or measuring AI-assisted workflow quality. Don't use for end-user feature work.
metadata:
  origin: ECC
model: inherit
effort: high
---

# Eval Harness Skill

A formal evaluation framework for Claude Code sessions, implementing eval-driven development (EDD) principles.

> **Status: prose-only methodology guidance.** The dataset-driven eval gate this framework once
> wired (`eval/run-eval.py` + its CI job) was deleted in the 2026-06-27 owner-authorized reset
> (`c452102`) and has not been rebuilt — see root `CLAUDE.md`'s Validation section. Everything below is
> design guidance you apply by hand; no CI job enforces it today. (Honest-status marker pattern
> adapted from semantica-agi/semantica's unbuilt-module flagging.)

## When to Activate

- Setting up eval-driven development (EDD) for AI-assisted workflows
- Defining pass/fail criteria for Claude Code task completion
- Measuring agent reliability with pass@k metrics
- Creating regression test suites for prompt or agent changes
- Benchmarking agent performance across model versions

## Philosophy

Eval-Driven Development treats evals as the "unit tests of AI development":
- Define expected behavior BEFORE implementation
- Run evals continuously during development
- Track regressions with each change
- Use pass@k metrics for reliability measurement

## Eval Types

### Capability Evals
Test if Claude can do something it couldn't before:
```markdown
[CAPABILITY EVAL: feature-name]
Task: Description of what Claude should accomplish
Success Criteria:
  - [ ] Criterion 1
  - [ ] Criterion 2
  - [ ] Criterion 3
Expected Output: Description of expected result
```

### Regression Evals
Ensure changes don't break existing functionality:
```markdown
[REGRESSION EVAL: feature-name]
Baseline: SHA or checkpoint name
Tests:
  - existing-test-1: PASS/FAIL
  - existing-test-2: PASS/FAIL
  - existing-test-3: PASS/FAIL
Result: X/Y passed (previously Y/Y)
```

## Grader Types

### 1. Code-Based Grader
Deterministic checks using code:
```bash
# Check if file contains expected pattern
grep -q "export function handleAuth" src/auth.ts && echo "PASS" || echo "FAIL"

# Check if tests pass
npm test -- --testPathPattern="auth" && echo "PASS" || echo "FAIL"

# Check if build succeeds
npm run build && echo "PASS" || echo "FAIL"
```

### 2. Rule-Based Grader
Regex or schema constraints — deterministic but pattern-based rather than exact:
```bash
# Check output matches expected JSON schema
python3 -c "import json,sys; json.load(sys.stdin)" < output.json && echo "PASS" || echo "FAIL"
```

### 3. Model-Based Grader
Use Claude to evaluate open-ended outputs:
```markdown
[MODEL GRADER PROMPT]
Evaluate the following code change:
1. Does it solve the stated problem?
2. Is it well-structured?
3. Are edge cases handled?
4. Is error handling appropriate?

Score: 1-5 (1=poor, 5=excellent)
Reasoning: [explanation]
```

### 4. Human Grader
Flag for manual review:
```markdown
[HUMAN REVIEW REQUIRED]
Change: Description of what changed
Reason: Why human review is needed
Risk Level: LOW/MEDIUM/HIGH
```

## Metrics

### pass@k
"At least one success in k attempts"
- pass@1: First attempt success rate
- pass@3: Success within 3 attempts
- Typical target: pass@3 > 90%

### pass^k
"All k trials succeed"
- Higher bar for reliability
- pass^3: 3 consecutive successes
- Use for critical paths

**Recommended thresholds:** capability evals pass@3 >= 0.90; regression evals pass^3 = 1.00 for release-critical paths.

## Eval Storage

Store evals in project:
```
.claude/
  evals/
    feature-xyz.md      # Eval definition
    feature-xyz.log     # Eval run history
    baseline.json       # Regression baselines
```

## Best Practices

1. **Define evals BEFORE coding** - Forces clear thinking about success criteria
2. **Run evals frequently** - Catch regressions early
3. **Track pass@k over time** - Monitor reliability trends
4. **Use code graders when possible** - Deterministic > probabilistic
5. **Human review for security** - Never fully automate security checks
6. **Keep evals fast** - Slow evals don't get run
7. **Version evals with code** - Evals are first-class artifacts

## Example: Adding Authentication

```markdown
## EVAL: add-authentication

### Phase 1: Define (10 min)
Capability Evals:
- [ ] User can register with email/password
- [ ] User can login with valid credentials
- [ ] Invalid credentials rejected with proper error
- [ ] Sessions persist across page reloads
- [ ] Logout clears session

Regression Evals:
- [ ] Public routes still accessible
- [ ] API responses unchanged
- [ ] Database schema compatible

### Phase 2: Implement (varies)
[Write code]

### Phase 3: Evaluate
Run each capability eval manually or via script, record PASS/FAIL. Run regression evals through the existing test suite: `npm test -- --testPathPattern="auth"`

### Phase 4: Report
EVAL REPORT: add-authentication
==============================
Capability: 5/5 passed (pass@3: 100%)
Regression: 3/3 passed (pass^3: 100%)
Status: SHIP IT
```

## Eval Anti-Patterns

- Overfitting prompts to known eval examples
- Measuring only happy-path outputs
- Ignoring cost and latency drift while chasing pass rates
- Allowing flaky graders in release gates

## Minimal Eval Artifact Layout

- `.claude/evals/<feature>.md` definition
- `.claude/evals/<feature>.log` run history
- `.claude/evals/baseline.json` regression baselines (when the eval has a regression variant)
- `docs/releases/<version>/eval-summary.md` release snapshot

## Completion criterion

Before calling an eval run done: verify every capability eval has a recorded PASS/FAIL, confirm every regression eval hits pass^k on release-critical paths, and check that the report states pass@k against its threshold — a run with no recorded verdict is abandoned, not done.
