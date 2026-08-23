# ADR 0010 — Mutation testing as an on-demand test-quality sensor (Shape B)

> **Status:** 🔴 **Rejected — stay parked** (operator ruling, 2026-08-23). Three fresh-context
> reviewers ran 2026-08-23; the steelman's attack won against the ADR as written, and the two
> structural reviewers' must-fixes plus my own primary-source checks confirmed the central value
> prop is misattributed and a key non-goal is actively defeated. Operator ruled to stay parked.
> NOT implemented — no skill built. The park's Recommendation #3 (periodic hand-run, reuse the
> committed XMLs after any gate edit) remains the standing mechanism. See the review section below.
> **This ADR is the record of *why* the un-park was declined — do not re-litigate without new
> evidence that answers the three convergent findings.**
> **Date:** 2026-08-23 · **Decider:** Operator (ruled 2026-08-23 — stay parked) · **Supersedes:** narrowly, the
> *park verdict* recorded in `docs/research/mutation-probe-results-2026-08-23.md` ("PARK the
> tool"), and only for the on-demand perimeter-scoped slice below. **Retains:** the park's two
> load-bearing halves — mutation-score is NOT a gauntlet/pre-commit gate, and the number comes
> from a deterministic engine, never from a model self-scoring.

## Problem

kbg's operating crux (`CLAUDE.md` §Architecture): a gate is a *deterministic verifier*, the model
is the *maker*, and the maker can never grade its own work. Yet kbg's only signal for **test
quality** today is exactly that forbidden shape — a model judging test honesty inferentially:
- `skills/blind-spot-hunter-shapes/SKILL.md:75-79` — shape 7 *reasons statically* whether a test is
  vacuous, then **names a mutation check for the operator to run** because the agent is read-only.
- `agents/code-reviewer.md` — behavioral-test-coverage lens, model judgment.

The 2026-08-23 mutation probe measured the cost of having no deterministic test-quality check: **both
deny gates (`irrecoverable.sh`, `worktree-guard.py`) had real fail-open deny paths that the green
test suite did not catch** — precisely where a weak oracle is most dangerous. The probe then
**parked** the tool.

## What was parked, and why the park was correct

The park (`mutation-probe-results-2026-08-23.md`) rejected a *broad, gauntlet-wired* mutation gate on
three findings that remain true and are NOT contested here:
1. **Non-determinism** — the full-run survivor *count* was 53/49/47 across three identical
   invocations (timing-sensitive kills). A flaky number cannot be a gate threshold.
2. **Cost** — ~22 min per gate-suite run; unfit for pre-commit or the gauntlet.
3. **Supply chain** — the bash-capable engine (`domohuhn/mutation-test`) is a ~26★ third-party
   pub.dev package installed at run time.

The park's verdict — "the value was the one audit, not a standing tool" — was reconfirmed on
2026-08-23 by a 3-verifier fan-out re-audit of the source article. **This ADR does not overturn any
of that.**

## What changed — why this is a different question than the park scored

The park evaluated a **broad gauntlet gate**. It never scored the strictly narrower shape the
re-audit surfaced (**Shape B**), which sidesteps all three park findings:

| Park finding | Shape B's answer |
|---|---|
| Non-determinism of the count | Uses **per-mutant verification** (this exact flip → this exact test fails), which IS deterministic. The noisy aggregate count is never the oracle. |
| 22-min cost unfit for gauntlet | **On-demand only** — operator names a target; never in pre-commit/gauntlet. |
| Supply-chain of the engine | **Graceful-skip if absent** + documented install; no auto-install; the dep is invoked, not vendored into the gate path. |

And Shape B closes a seam that **already exists in code**: blind-spot-hunter already *names* the
mutation check but nothing executes it. Shape B is that executor. **This session already ran the
technique by hand** — per-mutant flips proving the newly-added gate tests bite (`sudo`-unwrap,
fail-closed backstop, `sed --in-place`; each failed exactly its one target test). Shape B
systematizes that one proven manual move.

## Decision (proposed)

Ship a small **operator-invokable skill `skills/mutation-check/`** that, given an explicit target
file/dir + its test command, runs the appropriate mutation engine on a **copy** and reports
**per-mutant survivors + triage** (weak-oracle vs equivalent), reusing the committed engine config in
`docs/research/mutation-probe-2026-08-23/`. It is a *deterministic backstop to blind-spot-hunter's
inferential guess*, scoped first to the verifier/gate perimeter.

## Scope / Non-goals

**In:** the skill; ADR; a one-line seam pointer in blind-spot-hunter shape 7; a positive+negative
control self-test.
**Out (the park's valid half — preserved):** no gauntlet/pre-commit gate; no aggregate kill%
threshold; no CRAP score (declined on priority); no auto-invocation/self-start; no change to any
gate/verifier/SUT.

## Consequences

- **Positive:** converts kbg's one inferential test-quality signal into a deterministic one exactly
  at the crux-critical surface; makes blind-spot-hunter's shape-7 recommendation executable; gives a
  repeatable version of a technique that already caught real fail-opens this session.
- **Negative / risk:** (a) supply-chain surface of a 26★ pub.dev dep — mitigated by graceful-skip +
  pinned version + invoke-not-embed, and named here honestly; (b) an on-demand tool that is never run
  provides no protection — adoption depends on operator habit + the blind-spot-hunter pointer; (c)
  scope-creep risk toward a gauntlet gate — the Non-goals above are the guardrail, and any future
  gate is a *new* ADR, not an extension of this one.

## Alternatives considered

1. **Stay parked (status quo).** Strongest counter-argument, and the steelman the review must run:
   the park was reconfirmed hours ago; blind-spot-hunter + code-reviewer already cover test quality
   inferentially; an on-demand tool nobody runs is dead weight; every past autonomy/tooling addition
   kbg later retired started as a "small, scoped" build. If this steelman wins, this ADR is rejected.
2. **Shape A — general stack-detecting mutation skill (the "Hardener" role).** Broader; the missing
   5th pipeline agent. Deferred — larger surface, and the perimeter slice is where the doctrine fit
   is sharpest. Revisitable as its own ADR if Shape B proves its worth.
3. **CRAP score gate.** Declined — target CI owns maintainability; marginal signal over line
   coverage; needs coverage plumbing Shape B doesn't.

## Fresh-context review (2026-08-23)

Three independent reviewers read this ADR + the park verdict with no memory of the drafting
session. Verdicts:

- **Doctrine-fidelity:** HOLDS-WITH-CAVEATS — no maker-grades-itself violation is smuggled in (the
  engine is an independent verifier, not a model self-scoring). But two must-fix-before-acceptance:
  (1) the ADR borrows *kill-confirmation*'s determinism to vouch for a skill whose headline output is
  *survivor-detection* — the ~10%-false side; (2) the "only signal is inferential" premise is false —
  `skills/harness-audit/scripts/checks/27-test-honesty-tautology-detector-methodol.sh` is a
  deterministic (if shallow) test-quality signal that already exists.
- **Steelman-for-staying-parked:** ATTACK WINS against the ADR as written (does not permanently
  foreclose — the park deferred surface-promotion procedurally). Core: (1) Problem section
  understates existing coverage — `agents/code-reviewer.md:121-129` already does mutation-shaped
  weak-oracle detection with a filing **demand**; (2) "deterministic backstop" is misattributed — the
  skill automates the *noisy* half (enumerate survivors) and leaves the deterministic half (per-mutant
  hand-verify) as manual labor already done this session; (3) value delta over the park's own
  Recommendation #3 (periodic hand-run) reduces to a config-reuse convenience wrapper; (4) sole
  adoption mechanism (operator habit + a one-line pointer) is the class the repo has measured failing
  (`db-write-gate`, 5 bypasses); (5) the engine under-samples string-heavy gate code — exactly the
  perimeter Shape B aims at.
- **Boundary/scope-creep:** LEAKY — not merely prose-only, but an *active* drift force exists:
  `tests/scripts/test-run-gauntlet-wiring.sh:36-41` enumerates every `test-*` under `tests/`+`scripts/`
  with **no exclusion list** and fails unless each is wired into the gauntlet — so the promised
  engine-exercising self-test would be force-wired into the 22-min pre-push run, defeating non-goal #1.
  Also: no `disable-model-invocation` ⇒ ambient model-invocation possible; the "pinned version"
  mitigation is unbacked (`shasums-baseline.txt` hashes the SUTs, not the engine); Non-goals assert
  hard limits without the `(prose-only)` marker `METHODOLOGY.md:90` requires.

**Primary-source spot-checks (by the synthesizing session, not taken on the reviewers' word):**
`code-reviewer.md:121-129` weak-oracle lens + filing demand — CONFIRMED; park `:216-228` "survivor
lists must be spot-verified (~10% false); per-mutant verification is deterministic" — CONFIRMED;
`test-run-gauntlet-wiring.sh:36-41` no-exclusion sweep — CONFIRMED; check 27 exists — CONFIRMED.

## Decision outcome

**Recommendation: REJECT — stay parked.** Once the two overstated claims are corrected (the
determinism belongs to the manual step, not the skill; kbg is not "only inferential"), Shape B's real
delta over the park's already-standing Recommendation #3 (periodic hand-run, reuse the committed XMLs
after any gate edit) is a convenience wrapper — and it adds new costs the hand-run doesn't have
(gauntlet-wiring pressure, supply-chain steady-state, model-invocation ambiguity). The park's Rec #3
already captures the value at lower risk. This is the plan's explicit "steelman wins → stop, stay
parked" branch. The operator ruled stay parked on 2026-08-23; this ADR stands as the record of why.
