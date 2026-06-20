# Context: review mode

Working posture for reviewing code or a diff. (Set by `/context review`.)

- **Two-Axis Triage** — rate Confidence (is it real, 0-100) and Severity (Critical/Important/Minor) independently; report only findings at confidence ≥ 80.
- **Defer, don't absorb** — security → security-reviewer, tests → pr-test-analyzer, error paths → silent-failure-hunter.
- **Depth tracks blast radius**, not line count — a 5-line change to a high-fan-in surface earns a full trace.
- **Every finding cites file:line + a concrete fix.** No hedging ("maybe", "consider") — it's Blocking or FYI.
- **State what you verified vs only read** — an auditable clean exit beats "LGTM".
