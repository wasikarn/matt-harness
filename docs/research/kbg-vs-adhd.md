# KBG vs ADHD — the port decision (PR1 of `ideate-adhd-port`)

This document records what we considered, rejected, and kept when porting
the [adhd-agent](https://github.com/UditAkhourii/adhd) divergent-ideation
skill into kbg-harness. It is the sibling of the ideate source — the *why we built it this way* companion to the *how to run it* operational doc.

Read this before changing `skills/ideate/SKILL.md` or the algorithm in its
body. The choices recorded here are the contract PR1 ships against.

## What we considered

The five load-bearing techniques from the upstream ADHD skill
(`/tmp/adhd-repo/skills/adhd/SKILL.md`, `/tmp/adhd-repo/src/engine.ts`):

1. **Frame library** — 15 cognitive vantages that push the generator into
   corners it would not naturally go (hardware-eyes, regulator, ten-year-
   old, adversary, biology, logistics, game-design, markets, inversion,
   extreme-zero, extreme-infinite, remove-assumption, speedrunner,
   ant-colony, ops-3am). Source: `src/frames.ts:16-122`.
2. **2-phase Diverge→Focus wall** — strict mechanical split. Phase 1 has
   NO critic; Phase 2 turns the critic back on for score + cluster +
   deepen. Source: `engine.ts:28-59` (system prompts) and `engine.ts:247-
   303` (run loop). The wall is what keeps the generator unanchored.
3. **3-axis scoring formula** — `novelty × 0.35 + viability × 0.40 +
   fit × 0.25`, with viability as the gatekeeper weight because
   "brilliant unshippable" is the failure mode. Source: `engine.ts:135-
   137`.
4. **Trap pruning** — `trap` is a free-text reason field, not a score
   threshold. The scoring pass attaches a one-line reason; the
   shortlist excludes trapped ideas, but traps are reported separately
   so the user can read WHY. Source: `engine.ts:43-45` (SCORE_SYSTEM)
   and `engine.ts:275-280` (shortlist build).
5. **Deepen survivors** — top-K (default 3) get a second pass with
   sibling context, producing sketch + risk + first step + 3-5 child
   ideas. The "connecting the dots" move. Source: `engine.ts:177-229`.

These five are the load-bearing payload. Everything else is plumbing.

## What we rejected

Six things we explicitly did NOT port, with the reason each was
rejected.

- **The zod dependency.** Upstream `package.json` brings `zod` for
  runtime schema validation on LLM-emitted JSON. kbg's `npx`-free
  posture (see `CLAUDE.md` §"No bundled dependencies") plus the
  judgment that LLM JSON is too untyped for zod to catch the
  interesting failures (it can validate a `viability: number` but not
  a `viability: number that means what I want`) made the dependency
  pure ceremony. The skill body tells the host Claude to ask the
  generator for JSON and to do a thin shape-check inline.
- **`Math.random()` frame shuffle.** `frames.ts:132` uses
  `sort(() => Math.random() - 0.5)`. We replace this with a
  deterministic pick (rotating wildcard + round-robin through
  code/design tags) because kbg doctrine prefers the same prompt in
  the same session to produce reproducible output unless the user
  explicitly opts in to variation. Variation is a future option, not
  the default.
- **Same-model judge.** Upstream uses the same model class for
  generation, scoring, clustering, and deepening. kbg's
  `inferential-structural-judge` precedent (deleted in the v0.6.3 reset,
  never rebuilt — the agent file no longer exists; cited here for the
  design reasoning, not as a live reference) plus the 2×2 doctrine
  (`CLAUDE.md` §"LLM-judge circularity") treat the same-model judge as a
  covert L4 loop and a shared-blind-spots failure mode. PR1 keeps the 4 phases on the host
  Claude (which is the same model, so the same caveat applies), but
  the structure is engineered to be drop-in replaceable with a
  fresh-context critic agent — the skill body and the cross-
  references in `## Cross-references` call this out explicitly.
- **n=1 eval.** The upstream `EVALS.md` documents a single
  hand-curated run (`n=1`). kbg's eval posture (see
  `eval/run-eval.py`, `eval/datasets/`, and `MEMORY.md`
  §"Loop Engineering adoption issues") requires regression fixtures
  with machine-checkable assertions. PR2 ships
  `eval/regressions/ideate-fanout-cap.json` to lock the 2-wave
  fan-out, which is the most easily drift-broken part of the
  algorithm. PR1 is honest about the n=1 provenance by recording it
  in this file; the eval rigor limitation is *the single biggest
  reason this skill should be treated as experimental*, not a
  turnkey production tool.
- **No retry on parse failure.** Upstream `engine.ts:88-91` silently
  returns an empty branch on JSON parse failure, and `engine.ts:130-
  131` does the same for the score pass. This is fine for a research
  tool; for a kbg skill it is silent-failure territory
  (`kbg:silent-failure-hunter` would flag it). PR1 notes in the
  skill body that the host Claude should retry-or-surface parse
  failures rather than swallow them — kbg's "fail loud" posture.
- **`disable-model-invocation: true`.** Upstream ADHD is user-only
  (the user types `/adhd` explicitly). kbg doctrine
  (`CLAUDE.md`'s "Non-obvious gotchas" bullet on this flag) reserves
  the flag for surfaces where autonomous invocation would cross an
  *irreversible / external / destructive / governance* boundary. The
  ideate skill is none of those — it is local, reversible, and the
  load-bearing use case is *auto-fire on vague open-ended prompts the
  model would otherwise default on*. So we set the flag to `false`
  and bound the cost in two other ways: the F8.5 hard cap
  (`orchestrate SKILL.md:420`) and the explicit 2-wave callout in
  the skill body. Cost is governed by the cap, not by gating the
  model away from the use case.

## What we kept

The five techniques listed in §"What we considered", in their full
upstream form, with these kbg-specific bindings:

- All **15 frames** (`frames.ts:16-122`) ported verbatim as a table in
  `skills/ideate/references/frames.md`. The frame prompts are the
  algorithm — softening them produces less-divergent output, and we have
  no eval harness sensitive enough to measure the difference, so we do
  not soften.
- The **2-phase Diverge→Focus wall**, ported as §"Phase 1 — Diverge"
  and §"Phase 2 — Focus" in `skills/ideate/SKILL.md`, with the 5-Agent
  parallel call and the deepen-pass call structure intact. The wall
  is what makes the algorithm work; collapsing it kills idea quality
  per the upstream comment at `engine.ts:50-51` ("The critic
  strangles the generator").
- The **3-axis scoring formula** `total = novelty × 0.35 + viability
  × 0.40 + fit × 0.25`, ported verbatim. Viability highest because a
  brilliant unshippable idea is the dominant failure mode.
- The **isolation invariant** — the rule that Diverge branches MUST
  NOT see each other's output, ported as its own section in the
  skill body and enforced in the `userPrompt` payload shape. This is
  the load-bearing property the upstream code preserves at
  `engine.ts:251-258` (parallel `Promise.all` over a frame list with
  no shared state).
- The **output shape** (brief / wide set / converge / focus /
  provocation), ported as §"Output shape" in the skill body. The
  structure is the value: a wall of equally-weighted prose is one
  of the upstream's explicit anti-patterns.

## Open questions

All three original follow-ups were implemented as the v0.2.32/v0.2.33
`ideate` fine-tunes and are recorded in
`memory/ideate-adhd-fine-tunes.md`. This section is kept as a tombstone
so future agents do not re-derive the same gaps.

- **Per-session cost budget for auto-invocation.** Resolved by
  `hooks/session/ideate-budget-capture.sh` + the SessionStart budget
  advisory. The daily threshold defaults to 10 and is adjustable via
  `KBG_IDEATE_DAILY_THRESHOLD`.
- **Frame rotation across sessions.** Resolved by
  `hooks/session/ideate-rotate.sh`, which writes
  `~/.claude/state/ideate-rotation.json` and emits a deterministic
  5-frame rotation via `additionalContext`.

## Eval rigor limitation (explicit)

The upstream `adhd-agent` evaluation is `n=1`: a single hand-curated
demonstration in `EVALS.md`. There is no CI gating, no statistical
significance test, no comparison condition. The same author also
wrote the generation prompt, the scoring prompt, and the
demonstration — the same-model judge failure mode that
`inferential-structural-judge` is designed to avoid.

**Implication for kbg:** `skills/ideate/` ships with the algorithm
ported faithfully, plus a 2-wave fan-out regression fixture (PR2) to
lock the cost-envelope contract, but the *idea quality* of the
divergent pass is unverified beyond the upstream's n=1 demo. Treat
the skill as a *structured brainstorming tool*, not a *quality-
validated generator*. The pre-flight gate in the skill body is
designed to fail loud on tasks that don't merit the cost — that
is the strongest guarantee we can give without further eval work.
