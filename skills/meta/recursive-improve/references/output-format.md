# recursive-improve — iteration report template

Moved verbatim from SKILL.md's Output Format section (2026-08-23, 200-LOC cap refactor). Field
disambiguation (`not-done`/`routed_to_implement`/`dropped`/`drift_guard: n/a`) stays in
`output-format-disambiguation.md` — read both when emitting the Step 6 report.

```
recursive-improve — iteration <N> report
  observed:        <reader summary: gaps across N sessions> · <audit: C/W/I counts>
  proposed:        <N candidates>   routed_to_implement: <N — never reached Step 3, scope guard>
  approved:        <N>   (approve | revise | reject | unreachable; if Step 3 ran two asks,
                    report each outcome — e.g. "HIGH: unreachable, LOW/MED: approve")
  executed:        <N>   dropped: <N — and why>
  per candidate:
    - <name> · file:line | session | audit-id
        executor:  <agent>
        done_when: <observable check>
        status:    done | not-done (<reason>)
        delta:     <metric moved? gaps N→M / audit X→Y / n/a>
  drift_guard:     improved | flat | regressed | n/a (Verify not reached) (rollback: none|reverted|tuned|accepted+why)
  witness_diff:    <fleet changes, or "none">
  backlog:         <candidates past the cap / deferred, or "none">
```
