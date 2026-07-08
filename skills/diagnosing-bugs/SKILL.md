---
name: diagnosing-bugs
description: Diagnosis loop for hard bugs and perf regressions. Use when the user says 'debug', 'this is broken', 'not working', 'why is this happening', 'regression', 'crash', 'failing', or Thai 'เจอบั๊ก'/'ไม่ทำงาน'/'แก้บั๊กให้ที'/'ทำไมผิด'. Don't use for trivial typos.
metadata.origin: matt-pocock
---

# Diagnosing Bugs

A discipline for hard bugs. Skip phases only when explicitly justified.

When exploring the codebase, read `CONTEXT.md` (if it exists) to get a clear mental model of the relevant modules, and check ADRs in the area you're touching.

## Phase 1 — Build a feedback loop

**This is the skill.** Everything else is mechanical. If you have a **tight** pass/fail signal for the bug — one that goes red on _this_ bug — you will find the cause; bisection, hypothesis-testing, and instrumentation all just consume it. If you don't have one, no amount of staring at code will save you.

Spend disproportionate effort here. **Be aggressive. Be creative. Refuse to give up.**

### Ways to construct one — try them in roughly this order

1. **Failing test** at whatever seam reaches the bug — unit, integration, e2e.
2. **Curl / HTTP script** against a running dev server.
3. **CLI invocation** with a fixture input, diffing stdout against a known-good snapshot.
4. **Headless browser script** (Playwright / Puppeteer) — drives the UI, asserts on DOM/console/network.
5. **Replay a captured trace.** Save a real network request / payload / event log to disk; replay it through the code path in isolation.
6. **Throwaway harness.** Spin up a minimal subset of the system (one service, mocked deps) that exercises the bug code path with a single function call.
7. **Property / fuzz loop.** If the bug is "sometimes wrong output", run 1000 random inputs and look for the failure mode.
8. **Bisection harness.** If the bug appeared between two known states (commit, dataset, version), automate "boot at state X, check, repeat" so you can `git bisect run` it. If instead a test suite pollutes shared state (a test that only fails when run after another), bisect across test files with `scripts/find-polluter.sh <path_to_check> <test_glob>` — same technique, different axis.
9. **Differential loop.** Run the same input through old-version vs new-version (or two configs) and diff outputs.
10. **HITL bash script.** Last resort. If a human must click, drive _them_ with `scripts/hitl-loop.template.sh` so the loop is still structured. Captured output feeds back to you.

Build the right feedback loop, and the bug is 90% fixed.

### Tighten the loop

Treat the loop as a product. Once you have _a_ loop, **tighten** it:

- Can I make it faster? (Cache setup, skip unrelated init, narrow the test scope.)
- Can I make the signal sharper? (Assert on the specific symptom, not "didn't crash".)
- Can I make it more deterministic? (Pin time, seed RNG, isolate filesystem, freeze network.)

A 30-second flaky loop is barely better than no loop; a 2-second deterministic one is tight — a debugging superpower.

### Non-deterministic bugs

The goal is not a clean repro but a **higher reproduction rate**. Loop the trigger 100×, parallelise, add stress, narrow timing windows, inject sleeps. A 50%-flake bug is debuggable; 1% is not — keep raising the rate until it's debuggable.

### When you genuinely cannot build a loop

Stop and say so explicitly. List what you tried. Ask the user for: (a) access to whatever environment reproduces it, (b) a captured artifact (HAR file, log dump, core dump, screen recording with timestamps), or (c) permission to add temporary production instrumentation. Do **not** proceed to hypothesise without a loop.

### Completion criterion — a tight loop that goes red

Phase 1 is done when the loop is **tight** and **red-capable**: you can name **one command** — a script path, a test invocation, a curl — that you have **already run at least once** (paste the invocation and its output), and that is:

- [ ] **Red-capable** — it drives the actual bug code path and asserts the **user's exact symptom**, so it can go red on this bug and green once fixed. Not "runs without erroring" — it must be able to _catch this specific bug_.
- [ ] **Deterministic** — same verdict every run (flaky bugs: a pinned, high reproduction rate, per above).
- [ ] **Fast** — seconds, not minutes.
- [ ] **Agent-runnable** — you can run it unattended; a human in the loop only via `scripts/hitl-loop.template.sh`.

If you catch yourself reading code to build a theory before this command exists, **stop — jumping straight to a hypothesis is the exact failure this skill prevents.** No red-capable command, no Phase 2.

## Phase 2 — Reproduce + minimise

Run the loop. Watch it go red — the bug appears.

Confirm:

- [ ] The loop produces the failure mode the **user** described — not a different failure that happens to be nearby. Wrong bug = wrong fix.
- [ ] The failure is reproducible across multiple runs (or, for non-deterministic bugs, reproducible at a high enough rate to debug against).
- [ ] You have captured the exact symptom (error message, wrong output, slow timing) so later phases can verify the fix actually addresses it.

### Minimise

Once it's red, shrink the repro to the **smallest scenario that still goes red**. Cut inputs, callers, config, data, and steps **one at a time**, re-running the loop after each cut — keep only what's load-bearing for the failure.

Why bother: a minimal repro shrinks the hypothesis space in Phase 3 (fewer moving parts left to suspect) and becomes the clean regression test in Phase 5.

Done when **every remaining element is load-bearing** — removing any one of them makes the loop go green.

Do not proceed until you have reproduced **and** minimised.

## Phase 3 — Hypothesise

Generate **3–5 ranked hypotheses** before testing any of them. Single-hypothesis generation anchors on the first plausible idea.

Each hypothesis must be **falsifiable**: state the prediction it makes.

> Format: "If <X> is the cause, then <changing Y> will make the bug disappear / <changing Z> will make it worse."

If you cannot state the prediction, the hypothesis is a vibe — discard or sharpen it.

**Named bias guard — anchoring + confirmation.** The ranked-list requirement above is the anchoring guard (a single hypothesis anchors on the first plausible story); the falsifiability requirement is the confirmation guard (a hypothesis you can't disprove is one you'll unconsciously confirm). Full rung detail: `judgment-ladder.md` §"3. Gather and test assumptions" — read via Bash: `cat "${KBG_PLUGIN_ROOT}/docs/reference/judgment-ladder.md"`.

**Show the ranked list to the user before testing.** They often have domain knowledge that re-ranks instantly ("we just deployed a change to #3"), or know hypotheses they've already ruled out. Cheap checkpoint, big time saver. Don't block on it — proceed with your ranking if the user is AFK.

### Phase 3.5 — Probe discrimination (the gap that causes wrong root cause)

Single-hypothesis anchoring is the obvious trap. The **subtler** one: a probe that confirms H1 also confirms H2 because they predict the same observed signal. The bug "fixes," recurs in production, and the real cause was never ruled out.

**For each adjacent pair (H_n, H_{n+1})**, fill this before picking a probe:

| Question | Write this |
|---|---|
| **Shared signal?** | Does H1 and H2 predict the *same* observation at the boundary you're about to probe? (Y → cannot discriminate here) |
| **Discriminating boundary?** | Is there a *different* boundary where H1 and H2 predict *different* observations? (Y → probe there instead) |
| **Falsifying evidence for H1?** | What observation, if it appeared, would *disprove* H1? (If you can't name one, H1 is a vibe — re-sharpen) |
| **Cost of being wrong?** | If H1 is wrong, how much rework? Cheap → just probe. Expensive (data loss, security, multi-day fix) → must run adversarial verify or a discriminating probe |

**Three viable moves when H1 and H2 are signal-equivalent at every obvious boundary:**

1. **Find the discriminating boundary** — usually one layer deeper (the call *into* the suspect, not the call *out of* it; the row *before* the query, not the row *after*; the value *before* the transform, not *after*).
2. **Run two probes in parallel** at different boundaries — the one that contradicts one hypothesis confirms the other.
3. **Add the missing instrumentation that creates the boundary** — a counter, a log line at a seam that didn't exist, a throwaway assertion. This is the loop tightening the skill already prescribes; doing it for *discrimination* (not just confirmation) is the upgrade.

**Don't probe before this matrix is filled in for the top two hypotheses.** A confirming probe on a signal-equivalent pair is the #1 way to ship a fix that doesn't fix anything.

## Phase 4 — Instrument

Each probe must map to a specific prediction from Phase 3. **Change one variable at a time.**

Tool preference:

1. **Debugger / REPL inspection** if the env supports it. One breakpoint beats ten logs.
2. **Targeted logs** at the boundaries that distinguish hypotheses.
3. Never "log everything and grep".

**Named bias guard — anchoring (discriminating evidence).** If the #1 and #2 ranked hypotheses could plausibly produce the *same* observed signal, a probe that only confirms #1 doesn't rule out #2 — the wrong root cause can pass the gate below and the bug recurs after the "fix" lands. When the top two are plausibly signal-equivalent, the probe must discriminate between them (a boundary where they'd predict different outcomes), not just confirm the first.

**Tag every debug log** with a unique prefix, e.g. `[DEBUG-a4f2]`. Cleanup at the end becomes a single grep. Untagged logs survive; tagged logs die.

### Phase 4.5 — Evidence threshold (when is a hypothesis "confirmed"?)

"Confirmed" without a threshold is how root cause slips. The probe ran, the expected signal appeared, you wrote the fix — but the signal you saw could equally have come from H2, and you never checked. The Phase 3.5 discrimination matrix tells you *which* probe to run; this checklist tells you *what counts as success*.

**All four must hold before moving to Phase 5. If any is "no," the hypothesis is still a hypothesis — re-probe, fall back to the next-ranked, or stop and re-scope.**

- [ ] **Signal specificity** — the observed evidence *uniquely* matches H_n's prediction. If the same evidence also fits the #2 hypothesis, you've confirmed *either* — not H_n. (Phase 3.5's matrix would have caught this; use it as a recheck if you skipped it.)
- [ ] **Falsifiability demonstration** — you can name the observation that, if it had appeared, would have *disproved* H_n. If you can't, H_n wasn't really tested; the probe just "saw something." State the falsifier aloud (in the comment, in the commit message, in the chat with the user).
- [ ] **Reproducible at least 3×** — the confirming observation has fired at least 3 times across independent runs (different inputs, different timing, or at minimum different process invocations). One observation is anecdote. Three is data. (For non-deterministic bugs: raise the repro rate first per Phase 1's "non-deterministic branch" — do not lower the bar.)
- [ ] **Negative space checked** — at least one *adjacent* code path that's *not* affected by the bug was probed, and showed the expected "no signal" / "not the cause" result. This catches the "the bug is everywhere" false confirmation where H_n is true everywhere because the assumption is built into the codebase, not the bug.

**The most-skipped check is negative space.** It's also the one that catches the "fix it in three places and the bug comes back" pattern. If you can't find an adjacent path that *doesn't* have the bug, your model of the system is wrong — go back to Phase 2 (Localize) before Phase 5 (Fix).

**Perf branch.** For performance regressions, logs are usually wrong. Instead: establish a baseline measurement (timing harness, `performance.now()`, profiler, query plan), then bisect. Measure first, fix second.

**Gate before writing the fix.** Once a hypothesis is confirmed (expected signal appeared, is falsifiable, and would look different if the hypothesis were wrong), don't proceed straight to Phase 5. **AskUserQuestion** single-select: "Confirmed: hypothesis '[H description]' is supported by [evidence summary]. Approve and proceed to the fix?"
- `Approve — proceed to Phase 5 (Recommended when the instrumentation evidence is strong and reproducible)`
- `Reject — need more investigation (Recommended when evidence is weak, contradicted, or an untested higher-ranked hypothesis remains)`

This is the same checkpoint `/fix-bug` already runs when it mirrors this loop inline — applying to code has consequences a non-blocking ranking checkpoint (Phase 3) doesn't. Don't skip it just because this skill was invoked directly instead of through `/fix-bug`.

## Phase 5 — Fix + regression test

Write the regression test **before the fix** — but only if there is a **correct seam** for it.

A correct seam is one where the test exercises the **real bug pattern** as it occurs at the call site. If the only available seam is too shallow (single-caller test when the bug needs multiple callers, unit test that can't replicate the chain that triggered the bug), a regression test there gives false confidence.

### Phase 5.5 — Seam decision tree (pick the right test seam)

"Test seam" is binary in the skill today: exists or doesn't. Real life is graded. Walk this tree **before** writing the test — the wrong seam costs more than no test, because it gives green CI and zero protection.

```
Does the test fixture reproduce the exact input chain that triggered the bug?
├── NO — fixture simplifies one element (one caller, one config, one env state)
│   ├── Can the fixture be expanded cheaply? (≤30 min, no infra change)
│   │   ├── YES → expand the fixture, write the test there
│   │   └── NO  → STOP. No correct seam exists at this layer.
│   │             Note it (this IS the finding — architecture handoff).
│   │             Do not write a "best effort" test at the wrong seam.
│   └──
│
├── YES — fixture matches the real chain
│   ├── Does the test reach the code path that *actually* misbehaved?
│   │   ├── NO — test stays above the bug; passes for the wrong reason
│   │   │         → find a deeper seam, or accept "no correct seam"
│   │   └── YES — the test would have caught this bug
│   │       ├── Does the test have a single, named reason it can fail?
│   │       │   (e.g. "expected output X", not "should not error")
│   │       ├── NO  → sharpen the assertion. "Doesn't throw" is not a test.
│   │       └── YES → write the test here, watch it fail, apply fix, watch it pass
│   │
│   └── Is the failure mode visible without a full app boot?
│       ├── NO — bug only fires in real env (cluster of services, prod data shape)
│       │         → see "no correct seam" below; this is a structural finding
│       └── YES → seam is correct
│
└── NO correct seam at any layer (after the tree above)
    → This is the finding. Don't paper over with a unit test.
    → Note in the PR: "regression test for this bug is impossible at current seams"
    → Hand off to kbg:improve-codebase-architecture (Phase 6 last action).
```

**The "would have caught this bug" check is the load-bearing one.** Replay the original symptom through the test in your head: does the assertion fire *for the same reason* the user saw the bug? If it fires for a different reason (a downstream error, a different code path), the test will pass when the bug returns, and you'll be debugging this again in three months.

**If no correct seam exists, that itself is the finding.** Note it. The codebase architecture is preventing the bug from being locked down. Flag this for the next phase.

If a correct seam exists:

1. Turn the minimised repro into a failing test at that seam.
2. Watch it fail.
3. Apply the fix.
4. Watch it pass.
5. Re-run the Phase 1 feedback loop against the original (un-minimised) scenario.

## Phase 6 — Cleanup + post-mortem

Required before declaring done:

- [ ] Original repro no longer reproduces (re-run the Phase 1 loop)
- [ ] Regression test passes (or absence of seam is documented)
- [ ] All `[DEBUG-...]` instrumentation removed (`grep` the prefix)
- [ ] Throwaway prototypes deleted (or moved to a clearly-marked debug location)
- [ ] The hypothesis that turned out correct is stated in the commit / PR message — so the next debugger learns

**Then ask: what would have prevented this bug?** If the answer involves architectural change (no good test seam, tangled callers, hidden coupling) hand off to the `kbg:improve-codebase-architecture` skill with the specifics. Make the recommendation **after** the fix is in, not before — you have more information now than when you started.

---

## Named Model

This skill is a stitched reasoning scaffold, not a correctness oracle. The lenses it draws on (cc-thinking-skills):

- **Phase 1** — *feedback-loops* (reinforcing/balancing): tighten rate-of-feedback as the rate-limit on every later phase.
- **Phase 3.5** — *debiasing* (anti-anchoring + anti-confirmation): the probe must disprove H1, not just confirm it; *reversibility* + *opportunity-cost* frame the cost-of-being-wrong branch.
- **Phase 4.5** — *scientific-method* (hypotheses are world-claims, evidence must refute, not just fit) + *map-territory* (negative space = the territory your map misses).
- **Phase 5.5** — *systems-thinking* (tests that straddle the wrong boundary measure the wrong thing) + *theory-of-constraints* (where the test can't reach is the constraint).

Catalog + honesty caveat: read via Bash with `cat "${KBG_PLUGIN_ROOT}/docs/reference/reasoning-models.md"`.
