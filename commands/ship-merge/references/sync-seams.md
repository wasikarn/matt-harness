# Phase 2 step 6 — merge-command sync seam

Reference for `commands/ship-merge/COMMAND.md` Phase 2 step 6 (the server-side `gh pr merge`
call).

`skills/incident/references/hotfix-reference.md` Phase 4 duplicates this exact merge command
for the P0/P1 emergency path — the two are intentionally separate calls, not a shared
subroutine, since hotfix strips this phase's scored gate for speed. Hotfix's unconditional
`--admin` is a deliberate difference (an emergency merge always needs the bypass), not drift
from Phase 2 step 4's conditional `--admin` logic.

If you change the merge flags or the confirm-prompt shape in `COMMAND.md` Phase 2, check
whether hotfix's Phase 4 needs the matching edit.

**Checked 2026-08-10:** hotfix's Phase 4 already carries the equivalent
default-recommendation + consequence-stating language (v0.68.256) — this step's edit matched
that shape, no further edit was needed there at the time.
