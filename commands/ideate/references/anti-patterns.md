## Anti-patterns

These are how this skill goes wrong. Watch for them.

- **Convergence disguised as divergence.** Ten minor variations
  of one idea is not breadth. If every candidate shares the same
  underlying assumption, you have not diverged. You have
  decorated. Spread the frame picks.
- **Weird-for-weird's-sake with no convergence.** A pile of 30
  unsorted absurdities is as useless as one safe answer. Always
  converge with a real opinion.
- **Walls of equally-weighted prose.** Cluster, label, pull out
  the best. The output structure is half the value.
- **Refusing to commit.** After diverging, take a position on
  what is actually promising. "Here are 30 ideas, you decide" is
  a cop-out. Generate wide, but converge with a real opinion.
- **Skipping the isolation invariant.** If you simulate parallel
  branches by writing them sequentially in one context, you have
  not done ideate. You have done a wider single thought. The
  Agent/Task tool gives each branch a fresh context. Use it.
- **Collapsing Phase 1 + Phase 3 into one wave.** The 2-wave
  structure is a code contract, not a vibe — a single-wave variant
  of 8 agents would exceed the F8.5 hard cap (5 per wave). See
  COMMAND.md's "2-wave fan-out (load-bearing)" section for the full
  rationale and enforcement caveat.
- **Silent parse failures.** If a Diverge branch returns empty
  or unparseable, surface the failure to the user — do not
  pretend the run succeeded. The upstream `engine.ts:88-91`
  silent-empty return is *not* the kbg posture; see
  `mh:silent-failure-hunter` and COMMAND.md's "3-axis scoring rubric"
  section's note on `trap` being a free-text reason field rather than a
  silent drop.
- **Same-model judge treated as ground truth.** Phase 2 + 3 scoring runs on
  the same model class as the generators — advisory evidence, not ground
  truth. Full reasoning: COMMAND.md's "Phase 2 — Focus" section.
