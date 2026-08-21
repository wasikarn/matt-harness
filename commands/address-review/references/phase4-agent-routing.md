Conditional agent routing (COMMAND.md Phase 4, action 2), **launched in parallel**, for inline-edit clusters only (bug-shaped clusters get this routing from `/fix-bug`'s own Phase 7 — don't double-route):
   - Reviewer flagged error handling → `silent-failure-hunter` agent on the fix
   - Reviewer flagged auth/secrets/external input → `security-reviewer` agent on the fix
   - Reviewer flagged performance/algorithm (a complexity suggestion, not observable wrong
     behavior — that shape stays `bug-shaped` and routes via `/fix-bug` instead) →
     `performance-optimizer` agent on the fix
   - Reviewer flagged general correctness → `code-reviewer` agent on the fix
