# iterate-skill — design rationale, failure modes, integration notes

Moved verbatim from COMMAND.md (2026-08-23, 200-LOC cap refactor). Every rule here is also
enforced at its point of use in COMMAND.md's Steps; this file carries the why and the recap.

## Why this forks `kbg:recursive-improve`'s skeleton, not `skill-creator`'s `run_loop.py`

`run_loop.py` fully automates *description* tuning because triggering is mechanically
observable — it just watches which tool Claude calls. Body content has no equivalent mechanical
check; `skill-creator`'s own body-improvement loop is human-judged ("keep going until
the user says they're happy"), not auto-searched. This command's signal —
`kbg:review-fixtures`' two independent reviewers plus reconciliation — is better than one
self-grading pass, but it is **reviewer judgment, not a hard grounded score** the way
`harness-audit`'s CRIT/WARN count is for `recursive-improve`. That's why the ASK gate
is mandatory, not decoration: a loop whose stop condition is reviewer judgment needs a
human as the real check (CLAUDE.md's verifier-separation crux).

## Failure Modes to Avoid

- **Guessing a tally.** A `feedback.json` without `target_attributable` has no baseline — say so,
  don't invent one.
- **Treating an interrupted prior run as "never reviewed."** Fixtures with no feedback.json is a
  resume state, not a fresh start — check `candidate.diff` against the live file before assuming
  nothing happened.
- **Treating a user's claim as your own verification.** "I checked, it matches" is a reason to
  double-check quickly, not a substitute for reading the file yourself — and a claim about file
  state can go stale if another session touches the workspace before you act on it.
- **Skipping the ASK gate because a candidate "looks obviously right."** The signal is reviewer
  judgment, not a grounded score — the human gate is what makes that acceptable to act on at all.
- **Self-declaring `AskUserQuestion` unreachable without trying it.** Defaults to the real gate;
  the prose fallback is for genuine unreachability, not a shortcut.
- **Bumping the manifest per iteration.** Races concurrent sessions; bump once, at the end.
- **Rewriting the whole target file in one candidate.** Makes Verify's delta impossible to
  attribute to the specific findings it was meant to address.
- **Re-testing against a name-based skill/agent/command reference.** Silently serves the stale
  cached copy until a bump + reinstall happens — always hand fixture-regeneration agents the repo
  file path.

## Integration Notes

- **Composes:** `kbg:review-fixtures` (the Observe/Verify signal source — this command does not
  reimplement its reviewer dispatch or reconciliation) · `skill-creator` (fixture-generation
  convention for Act) · `kbg:recursive-improve` (the gate language and rollback policy this loop's
  ASK/Surface steps reuse verbatim).
- **METHODOLOGY:** Rule 4 (loop until verified) · Rule 1's verifier-separation crux (reviewer
  judgment ≠ a grounded score — the human gate is the real check) · Rule 2 (this command exists
  because a real request surfaced the gap; don't extend its scope speculatively).
