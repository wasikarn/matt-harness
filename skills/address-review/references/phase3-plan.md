**Goal**: Cluster + order the actionable threads. Identify which ones route to `mattpocock-skills:diagnosing-bugs`.

**Actions**:
1. Cluster related comments — same file, same concern, same fix. One cluster → one commit (where possible).
2. Order clusters: critical (security / data correctness) → high → low. Wontfix / clarify / out-of-scope clusters skip implementation; queued for Phase 5.
3. Mark bug-shaped clusters for `mattpocock-skills:diagnosing-bugs` delegation:
   - Reviewer described observable wrong behavior + can be reproduced
   - Reviewer's concern is a missing edge case in a code path
4. Present plan to user. Confirm before Phase 4 — a plain-text acknowledgment is enough here (unlike Phase 2/5's `AskUserQuestion` gates): the plan is a re-ordering of choices the user already approved in Phase 2, not a new classification decision.
