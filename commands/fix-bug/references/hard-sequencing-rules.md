# Hard Sequencing Rules — full detail

Non-negotiable ordering constraints derived from the debug-mantra discipline. Violating them is
the #1 cause of fixing the wrong thing. Each is independently enforced by a real gate in its
named phase (see COMMAND.md); this file is the fuller rationale for the condensed index there.

1. **No hypothesis before deterministic repro.** If the repro isn't reliable, STOP. Don't guess
   at causes when you can't prove the effect. (Enforced: Phase 1 step 4.)
2. **No fix before confirmed hypothesis.** The fix targets the confirmed mechanism, not a ranked
   list of possibilities. If the top hypothesis turns out wrong after instrumentation, fall back
   and re-rank — don't patch on a hunch. (Enforced: Phase 3 step 7 gate.)
3. **No cleanup before regression test passes.** Strip instrumentation, run full suite, confirm
   green. Then clean up temporary files or debug branches. (Enforced: Phase 5 REFACTOR step.)
4. **No commit before distinguishes-or-it-doesn't check.** Phase 6 must pass before the fix is
   considered complete. A green test that doesn't actually catch the bug is worse than no test —
   it provides false confidence. (Enforced: Phase 6 step 3, required before Phase 7.)
5. **Record every run.** Each repro attempt, each instrumentation result, each hypothesis test
   is a ledger entry. If you're on the third hypothesis and still unsure, re-read the ledger —
   the pattern is in the data, not in your head. (Enforced: Phase 1 step 7, Phase 3 step 5.)
