# Phase 5: TDD opt-out — full procedure

Only when the test framework can't encode the bug type — visual regression, hard race
condition needing dedicated tooling, integration boundary with no test harness:

- Tell the user TDD is being skipped and why.
- Implement the fix directly. Re-run minimised repro to confirm it's gone. Run full suite.
- Phase 6 becomes the test-quality gate via revert-and-verify.
