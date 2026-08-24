# fix-bug: Integration Notes (Project-Specific)

- **METHODOLOGY alignment**: Rule 1 (Decision-sizing triad) → Phases 1-3. Surgical changes → Phase 4 default. Model only for judgment → Phase 1 repro must be deterministic, not Claude-asserted. Rule 4 (verify-intent loop) → Phase 6 distinguishes-or-it-doesn't check. Abort loud → Phase 1 abort if no repro.
- **code-review-graph MCP**: Phase 2 for structural lookup; the orchestrating session (not the reviewer agents, which have no MCP grant) runs impact-radius queries in Phase 7 before spawning review — reviewer agents escalate blast-radius depth via grep.
- **`diagnosing-bugs` and `tdd` are built in as DEFAULTS, not alternatives**:
  - Phase 1 (Reproduce + Minimise) and Phase 3 (Hypothesize + Instrument) inline `diagnosing-bugs`'s core loop so the full workflow lives in one document. Don't separately invoke `diagnosing-bugs` from within `/fix-bug` — it's already running.
  - Phase 5 defaults to `tdd`'s red-green-refactor. Opt out only when the test framework can't encode the bug type (visual regression, hard race condition).
  - Use standalone `diagnosing-bugs` for understand-only loops (e.g. characterising a flaky test before deciding whether to fix it).
  - Use standalone `tdd` for greenfield TDD on new features, not bug fixes.
- **Hooks active**: `hooks/gates/irrecoverable.sh` (destructive Bash/git/SQL patterns) and `hooks/gates/verifier-protect.sh` (hardcoded `/Users/` paths, folded from the deleted `path-hardcode.sh` 2026-07-03) run automatically. Don't bypass.
- **Agent routing reference**: silent-failure-hunter (error-handling audit), the per-language reviewers (test-coverage + comment accuracy), security-reviewer (auth/secrets/OWASP), performance-optimizer (algorithm/query-pattern root causes).
