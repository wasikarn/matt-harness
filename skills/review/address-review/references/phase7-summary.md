**Goal**: Document the response cycle.

**Actions**:
1. Mark all todos complete.
2. Summarize:
   - PR # and URL
   - Threads handled — breakdown by category (fixed / wontfix / clarify / out-of-scope)
   - Review-body items acknowledged (separate count, from Phase 5 step 4 — not folded into the thread breakdown above, since it was never a thread)
   - Commits added with sha → thread mapping
   - CI state from Phase 6
   - **Suggested next step:**
     - Fixes pushed, awaiting re-review → await reviewer; ping if urgent
     - Reviewer approves on push        → mh:ship-merge
     - Another pass wanted before merge → mattpocock-skills:code-review
     - wontfix-heavy and abandoned      → `gh pr close <n>` — "abandoned" means the user has explicitly said they're not pursuing this PR further (dropped the effort, superseded by other work, priorities changed). It is never inferable from wontfix density alone — a session where every thread got a substantive wontfix reply is NOT "abandoned" by that fact; see the two bullets below for that exact shape, both of which route to waiting or to nothing further needed, not to closing.
     - Pushback posted, nothing to push, at least one required reviewer's block still stands → Phase 6 step 3 already re-requested review from every stale required reviewer — now await their responses to the rationale; escalate if unresponsive. Don't reach for `gh pr close` here — no code changed doesn't mean the effort is abandoned, it means the ball is in the reviewer's court.
     - Pushback posted, nothing to push, no required reviewer's block stands (either no reviewer's `CHANGES_REQUESTED` is outstanding at all, or only a non-required reviewer's is) → nothing further to do on the review-state axis; only a required reviewer's `CHANGES_REQUESTED` blocks merge on that axis (CI and merge-conflict state were already checked separately in Phase 6 step 4), and the reply already posted is sufficient. Don't reach for `gh pr close` here either — the same "no code changed doesn't mean abandoned" reasoning applies regardless of whether any reviewer happens to be mid-review.

