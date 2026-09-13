---
type: llm
focus: trace
---
The agent's own contract: `total`, `shortlist`, `runnerUp.ideaId`, `nonObviousPick`, and `traps`
"come from `scripts/rank.py`... copy them verbatim. You own the scores and every reason string, not
the arithmetic." The trace contains a Bash call to `rank.py` and its JSON stdout (`totals`,
`shortlist`, `runnerUp`, `nonObviousPick`, `traps`). Score 1 if the final relayed JSON's
`scores.*.total`, `shortlist`, `runnerUp.ideaId`/`runnerUp` (or null), `nonObviousPick`, and `traps`
match that `rank.py` stdout exactly (same ids, same order, same numbers to the shown precision) —
i.e. the model copied the script's output rather than re-deriving or adjusting any of these fields
by hand. Score 0 if any of these fields disagree with what `rank.py` actually returned in the
trace, or if no `rank.py` invocation exists in the trace to compare against.
