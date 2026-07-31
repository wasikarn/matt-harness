# Address Review — Integration Notes (Project-Specific)

- **METHODOLOGY alignment**: Rule 1 (Decision-sizing triad) → Phases 1-3 (understand all threads + classify + plan before editing). Surface conflicts, don't average → Phase 2 forces explicit per-thread classification, never "kind of fix". Rule 4 (verify-intent loop) → Phase 4 cluster tests + Phase 6 CI check. Abort loud → Phase 5 verify-count gate aborts if any thread is missed.
- **Memory dependencies**:
  - `feedback_reply_after_pr_fix.md` — Phase 5 is the codified version of "per-thread reply + cite sha = part of done"
  - `feedback_prefer_gh_cli_for_github.md` — all GitHub ops via gh, not curl
- **`/fix-bug` delegation**: Phase 4 invokes `/fix-bug` for bug-shaped comments. `/fix-bug` usually returns with its own commit sha — capture it for Phase 5 citation. It can also legitimately stall with no commit (see Phase 4 step 2); that outcome re-classifies the cluster instead. Don't run /fix-bug recursively per-comment; cluster first, then one /fix-bug per cluster.
- **Hooks active**: `hooks/gates/irrecoverable.sh` (destructive Bash/git patterns) runs automatically on every Bash call during commits.
- **Agent routing reference**: silent-failure-hunter (error-handling regressions in fixes), security-reviewer (auth/secrets fixes), code-reviewer (general correctness regression on fixes, including its comment-accuracy lens if the fix added/changed docstrings).
- **Resolves threads only on explicit per-run opt-in (default off)**: GitHub's "Resolve conversation" is a separate action from posting a reply — Phase 5 step 1 asks once per run whether to auto-resolve `actionable + fixed` threads via the `resolveReviewThread` GraphQL mutation. Default is "leave open" so the reviewer verifies and resolves; `wontfix` / `clarify` / `out-of-scope` threads are never auto-resolved regardless of the choice.
- **Fork PRs**: If the PR is from a fork, `gh api` calls need explicit `--repo <upstream-owner>/<repo>` to target the right repo. Phase 1 step 1 captures `nameWithOwner` for this purpose.
