# Phase 7: agent routing — full trigger criteria

Full detail for the conditional routing table in COMMAND.md Phase 7 step 1.

- **Error-handling** (new/modified try-catch, fallbacks, exception flow) → `silent-failure-hunter`
- **Tests added/modified** → `code-reviewer` (behavioral test-coverage lens)
- **Auth / secrets / external input** → `security-reviewer`
- **Comments added/modified, or a shared function's behavior changed** (check other callers of
  the touched function for comments describing the old behavior, even in files the fix didn't
  edit — a comma-strip workaround's own comment going stale after the fix lands upstream is
  exactly this case) → `code-reviewer` (comment-accuracy lens)
- **Performance-shaped root cause** (Phase 3's confirmed hypothesis was an algorithm,
  data-structure, or query-pattern issue — an O(n²) loop, N+1 queries, a resort-per-update, or
  similar — not a plain logic error; Phase 1's own failure-signal list already includes "perf
  number" as a valid repro target) → `performance-optimizer`, to confirm the fix actually
  changes the complexity class rather than patching the symptom at the same asymptotic cost.
- If the fix touched none of the above (rare for non-trivial bugs) → route to `code-reviewer`
  agent for a general correctness pass against Phase 4 strategy.
