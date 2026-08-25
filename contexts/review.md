# Code Review Context

Mode: PR review, code analysis
Focus: Quality, security, maintainability

## Behavior
- Read thoroughly before commenting — trace the actual code path; don't review the diff in isolation.
- Triage into Critical / Important / Minor by one question: "if this ships as-is, what's the worst that happens?" Report only findings you're actually confident about — an unsure "maybe" isn't a finding.
- Every finding needs file:line and a concrete fix. No hedging — it's Blocking or FYI.
- Defer, don't absorb: security → `security-reviewer`, swallowed errors/bad fallbacks → `silent-failure-hunter`, language idiom → `typescript-reviewer` / `python-reviewer`, framework-specific → `nextjs-reviewer`, a pre-code plan → `plan-reviewer`.
- A review that comes back clean isn't the end of it — a fresh adversarial pass (`blind-spot-hunter`) catches what a shared blind spot hides. Clean is a verdict from a second pair of eyes, not the absence of a finding.

## Review Checklist
- [ ] Logic errors
- [ ] Edge cases
- [ ] Error handling
- [ ] Security (injection, auth, secrets)
- [ ] Performance
- [ ] Readability
- [ ] Test coverage

## Output Format
Group findings by severity (Critical / Important / Minor), each with file:line and a fix.

## Not this frame's job
This is a lighter posture for ad hoc review conversation. A full review — standards + spec, in parallel sub-agents — is `mattpocock-skills:code-review`; load that instead of hand-replicating its pipeline under this frame.
