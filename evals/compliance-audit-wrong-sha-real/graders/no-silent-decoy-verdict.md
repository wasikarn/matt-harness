---
type: regex
pattern: '(?:(?!decoy|detached\s+worktree|pinned).){0,150}\b(double|app\.py)\b[^.\n]{0,60}\b(missing|absent|not (?:found|implemented|present))\b(?!.{0,150}\b(?:decoy|detached\s+worktree|pinned)\b)'
flags: i
match: not_contains
target: last_message
---
This pattern only matches if the report says `double()`/`app.py` is missing or absent — which is
only true of the decoy commit checked out on disk, not of `plan-head` (the tag actually named in
the audit request). A match here proves the SHA pin was silently ignored in favor of whatever was
already checked out in `target-repo`.

Deep-audit 2026-09-07: the earlier version of this pattern had no exclusion window, so it false-
failed a CORRECT report that explains the decoy while still using the right pinned SHA (e.g. "The
decoy working tree has app.py missing, so I used a detached worktree at plan-head." — exactly the
intended, correct behavior per `criteria.md`'s own second sentence). The pattern now requires the
missing/absent claim to appear with no "decoy"/"detached worktree"/"pinned" acknowledgment within
150 chars on either side — a report that explains the decoy anywhere near the claim reads as
correct; one that doesn't reads as having silently ignored the SHA pin.
