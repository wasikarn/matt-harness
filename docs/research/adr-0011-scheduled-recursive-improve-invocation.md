# ADR 0011 — Scheduled invocation of recursive-improve (candidate 3, Option B)

> **Status:** 🟡 Proposed — awaiting operator decision. Not implemented; no cron job, launchd
> config, or code shipped alongside this document.
> **Date:** 2026-08-28 · **Decider:** Operator (not yet ruled).
> **Relationship to prior ADRs:** Does **not** supersede ADR 0006 or ADR 0009. ADR 0009's own
> "What this ADR does NOT authorize" section names `recursive-improve` explicitly as **out of
> scope** for its auto-continue carve-out, and its retained-invariants list keeps "the
> no-model-self-**launch** invariant (launchd/cron/`claude -p` self-start)" unmodified. This is
> the first proposal that would touch that specific retained invariant — a new question, not an
> extension of an already-granted exception.

## Problem

The Warp self-improving-agents article audit (`docs/research/
warp-self-improving-agents-article-audit-2026-08-28.md`, candidate 3) asked whether
`recursive-improve`'s signal-mining should run on a schedule instead of only when the operator
explicitly invokes it. Two of its three Observe-step signals (`gate-journal-summary.sh`,
`feedback-surface-scan.py`) only carry data that exists on the operator's own local machine —
confirmed while building `.github/workflows/harness-audit-drift.yml` (v0.68.538), which is
deliberately scoped to just the CI-portable third signal (`harness-audit`) for exactly this
reason. That workflow answers the CI half of candidate 3. This ADR is the remaining half: would
a **local**, operator-machine-scheduled invocation of `recursive-improve` itself be safe and
worth building.

## What this ADR proposes

A local (not CI) cron/launchd job on the operator's own machine, periodically running:

```
claude -p "/mh:recursive-improve" --permission-mode dontAsk
```

The `--permission-mode dontAsk` flag is load-bearing, not optional — verified this session
(`code.claude.com/docs/en/agent-sdk/headless`) that bare `-p` defaults to Manual mode, under
which an unanswered `AskUserQuestion` has no timeout and hangs indefinitely rather than failing
closed. `recursive-improve/SKILL.md` was corrected in the same commit that ships alongside this
ADR (v0.68.538) to state this explicitly.

With that flag: Observe and Propose run for real, with access to the real local signals. Step
3's `AskUserQuestion` gate is guaranteed **denied** (not merely unanswered) — the skill renders
its candidate list as numbered prose and stops at analysis-only, per its own documented behavior.
**Step 4 (Act) is categorically unreachable** from this invocation shape — there is no code path
from a denied `AskUserQuestion` to a mutation. Where the rendered candidate list should land for
the operator to read later (a local file? a note appended somewhere?) is an open design question
this ADR does not resolve.

## Why this needs a fresh ADR, not a reading of ADR 0009

ADR 0009's own text, quoted directly:

> **Retains:** the maker≠checker *principle*, the computational merge-gate, the no-model-self-**launch** invariant (launchd/cron/`claude -p` self-start), and the "model confidence is never the auto-act signal" rule.

and, in its "What this ADR does NOT authorize" section:

> Auto-loop on any loop other than review→fix (not `recursive-improve`, not `iterate-skill` — those stay human-started per iteration; their stop conditions are different and this ADR's evidence doesn't extend to them).

Both sentences name this exact proposal and exclude it. ADR 0009's carve-out is narrow by its own
account: auto-*continuing* a loop a human already started interactively, per round, inside one
session — never a scheduler cold-*starting* a session from zero. This proposal is the
cold-start case, for a different skill, with different evidence. It is squarely outside what
ADR 0009 already granted.

## Steelman for building it

- The fail-closed mechanism is real and verifiable, given the SKILL.md fix and the explicit
  `dontAsk` flag — not a hopeful assumption.
- Mutation risk is structurally zero: Step 4 is unreachable, not merely unlikely, from a denied
  `AskUserQuestion`.
- Matches Warp's own real design once the merge/mutation boundary is understood as equivalent to
  Step 3's gate — confirmed this session (Warp's article, unhedged: "A human reviews, approves,
  and merges... that final human step closes the loop and keeps a person in control of what
  actually changes"). The schedule reaches through Propose/PR-open in Warp's design; merge stays
  manual. This proposal places the same boundary at Observe/Propose vs. Act.
- Closes a real value gap: without any schedule, the local-only signals (gate journal, feedback
  clusters) only get read whenever the operator happens to invoke `recursive-improve` manually —
  comparatively rare, per `skills/meta/learn/SKILL.md`'s own usage counts for a related skill.

## Steelman against

- ADR 0006/0009's language is "no model self-**start**," not "no unattended mutation." That
  distinction is deliberate, not incidental: the maker≠checker crux argues a model should never
  be the one whose own schedule decides when to reconsider its governing instructions, even for
  a read-only Observe pass that can't itself mutate anything. A scheduled process cold-starting a
  real session — regardless of what it's permitted to do once running — is the self-start the
  invariant names.
- This is structurally close to the pattern ADR 0009's own Context section records being refused
  4× on 2026-07-01 (a "reasoning governance runtime" recurring in different framings, each
  colliding with the same crux) — a scheduled trigger for the model to reconsider/re-plan,
  presented as safe because "nothing will actually happen." ADR 0009 needed 5 fresh-context
  reviewers and a multi-round adversarial pass before the operator accepted even the *narrower*,
  already-precedented case (continuing a session a human had already started). This proposal is
  broader (cold self-launch) and has had zero adversarial review — this document is a single
  session's drafting pass, not a reviewed artifact.
- Real, non-hypothetical cost: a launchd plist or cron entry that lives outside the git repo
  (machine-specific, not something a push ships or a fresh clone inherits), a still-undesigned
  place for output to land, and ongoing per-machine maintenance the operator would own personally.

## Decision

**Not made by this document.** This ADR exists to give the operator a scoped,
evidence-grounded artifact to rule on — it deliberately doesn't recommend a verdict, since
pushing toward one is exactly the kind of self-interested judgment call this repo's own doctrine
argues a model shouldn't make about loosening its own operating constraints.

## What this ADR does NOT authorize

- Nothing in this document changes runtime behavior by itself. No cron job, launchd config, or
  code was created alongside it.
- If accepted: still requires resolving where rendered output lands, and — following ADR 0009's
  own precedent for a much narrower case — likely a multi-reviewer adversarial pass before
  implementation, since this would be the first-ever exception to the no-self-launch invariant.

## Revisit trigger

N/A until the operator rules. If accepted, standard practice per ADR 0009's own process (a
fresh-context adversarial review before shipping) applies before any implementation, not this
draft alone.
