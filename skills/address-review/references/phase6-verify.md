**Goal**: Move the PR back to reviewer's queue + confirm CI is happy.

**Actions**:
1. Push all Phase 4 commits if not already pushed: `git push`.
2. If the PR was draft (state changed during work) → `gh pr ready <n>`.
3. Re-request review — `gh pr edit <n> --add-reviewer <user>` (comma-separate multiple logins in one call, e.g. `--add-reviewer <user1>,<user2>`, when more than one reviewer needs it; or `gh api ... requested_reviewers`) — in either of two cases: the previous review was dismissed-on-push (re-request whichever reviewer(s) got dismissed), or zero commits were pushed this session but every thread got a substantive reply (wontfix/clarify rationale) and at least one **required** reviewer's review state is still `CHANGES_REQUESTED` (re-request every required reviewer still in that state, not just one, if more than one qualifies). Posting inline replies doesn't change a reviewer's review state on GitHub — only a re-request or a new review submission does — so a pushback-heavy, zero-commit session still needs this step to put the PR back on every stale required reviewer's radar. (A non-required reviewer's stale `CHANGES_REQUESTED` doesn't block merge, so re-requesting isn't the actionable lever there — a reply is enough. "Required" tracks GitHub's actual merge-blocking mechanic: a reviewer with write/admin/owner access whose Request Changes review stands, regardless of formal branch-protection listing — the two usually coincide, but if a stale `CHANGES_REQUESTED` comes from someone outside the required-reviewers list, verify their permission level before treating it as non-blocking, e.g. `gh api repos/<owner>/<repo>/collaborators/<user>/permission`.)
4. Check CI: `gh pr checks <n>`. If failures, surface to user before declaring done.
5. Output:
   - PR number + URL
   - Commits pushed in this session (sha + 1-line)
   - Thread-to-sha mapping for the user's records
   - CI state
