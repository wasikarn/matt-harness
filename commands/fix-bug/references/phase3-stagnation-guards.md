# Phase 3: no-progress halts — full illustrative detail

The condensed trigger conditions for these three guards live inline in COMMAND.md Phase 3
step 4 (stagnation guards — NOT retry caps; don't borrow the retry-cap vocabulary, this is a
different metric). Each routes to the step-7 gate's "Reject — need more investigation" branch,
never to more unattended rounds. Full illustrative wording:

- **Stall** — two instrumentation rounds return the *same missing-evidence result for the same
  failure signal* → stop re-ranking and go to the gate. ("Same error twice in a row: you're
  guessing, not fixing.")
- **Degrading** — confidence/progress goes *backwards* (each round contradicts the last), not
  just standing still → stop and go to the gate.
- **Reachable-source skip** — don't exit "blocked" on an inference when a real source/log was
  reachable but unread; read it, or route the block to the gate. "Blocked" must mean a real
  wall, not an unchecked assumption.
