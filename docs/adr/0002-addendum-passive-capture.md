# ADR 0002 — Addendum: Passive Learning-Capture (capture half only)

> **Note (2026-06-25):** Unaffected by [ADR 0006](0006-ecc-aligned-operating-model.md) — capture is advisory, apply is human-gated, no autonomy flag involved.

- **Status**: Accepted (extends [ADR 0002](0002-autonomy-invariant.md))
- **Date**: 2026-06-21
- **Decider**: Owner
- **Operating point**: Maximal-bounded (locked; see
  [`docs/research/passive-learning-capture-design.md`](../research/passive-learning-capture-design.md))
- **Scope**: Records that kbg adopts the **capture half** of ECC's continuous-learning
  flywheel (observe → queue) as a **default-OFF, advisory-only computational-FB sensor**,
  and **rejects the apply half** (confidence → auto-inject) that makes ECC a model-as-gate.

## Why this is an ADR 0002 addendum, not ADR 0004

The architecture ADR 0002 fixed is **unchanged**: advisory sensors *journal*, they do not
*gate*; APPLY stays human-gated. `learn-capture.sh` is a new advisory sensor of exactly the
class ADR 0002 + the CLAUDE.md 2×2 "advisory only" doctrine already govern (it sits beside
`verification-gate.sh` and `inferential-structural-judge`, which predate ADR 0003 and are
**not** L3-loop machinery). No architectural axis moves, so no superseding ADR is needed —
only this append-only addendum. A standalone ADR 0004 was the alternative if the owner had
wanted to move the apply boundary; he did not (Maximal-bounded keeps the human gate).

## The clean seam (what we lift, what we leave)

ECC's flywheel is `observe.sh` → self-launched `observer-loop.sh` daemon → headless
`claude --print` prompted *"Do NOT ask for permission … just write"* → confidence ≥0.7 →
`session-start.js` **auto-injects** the top instincts into every session's `additionalContext`
(verified on disk 2026-06-21). The capture (observe → queue) is computational and safe; the
apply (confidence → auto-inject, with no human in the loop) is the model-as-gate ADR 0002
forbids. We lift the left half and replace the gate with **human-at-the-gate** (`kbg:learn`'s
`AskUserQuestion`) or **human-at-push** (an approved L3 `recursive-improve --auto` run).

| Property | This addendum's posture | Enforced by |
|---|---|---|
| Default state | **ON** (opt out with `KBG_LEARN_CAPTURE=0`) — flipped v0.3.9; see "Default flip" below | `learn-capture.sh` early-exit |
| Repo writes | NEVER (queue is out-of-repo at `~/.claude/projects/<slug>/memory/_candidates/`) | path is outside any repo + outside the L3 cage |
| permissionDecision | NEVER emitted (journal + queue only, exit 0 always) | audit **#47** (CRIT) + critical-hooks suite |
| Confidence | ORDERING signal only — no value ever triggers an action | audit **#47** (CRIT) on any `confidence >= …` gate |
| APPLY | human-gated (`kbg:learn` `AskUserQuestion`, or L3 push Gate-2) | unchanged from ADR 0002 |

## Default flip — ON (v0.3.9, 2026-06-21)

Shipped default-**OFF** (v0.3.7), flipped default-**ON** (opt-out) at the owner's request.
This does **not** touch the invariant: it is APPLY that must stay human-gated, and APPLY is
unchanged (`kbg:learn`'s `AskUserQuestion`). CAPTURE was designed to be automatic from the start
(see "CAPTURE is automatic (passive)" above); OFF was **rollout conservatism**, not an invariant
requirement. The flip is also more coherent with *why* the feature exists — the owner forgets to
run `kbg:learn`, so they would equally forget to `export KBG_LEARN_CAPTURE=1`; a default the user
must remember reproduces the exact failure mode the feature addresses.

**Scope (owner decision):** default-ON applies to **all projects** the kbg plugin is active in,
not just kbg-harness — captured corrections/preferences from any repo land in that repo's
out-of-repo queue. Mitigations: secret-scrub (whole-row drop), out-of-repo plaintext on the
owner's own machine, APPLY still gated. Opt out per-shell/session with `KBG_LEARN_CAPTURE=0`, or
per-hook with `CLAUDE_DISABLED_HOOKS=learn-capture`. Reversible (one-line gate flip).

## The relaxation this records (honesty)

`skills/learn/SKILL.md` previously carried a `## Autonomy posture (load-bearing)` block at
:18-20 stating *"There is **no** SessionEnd auto-mining hook."* That stance is **consciously
relaxed**: there is now a SessionEnd hook, but it is **capture-only** — it stages candidates,
it does not mine-and-apply. The load-bearing half (APPLY is human-gated, nothing is written to
the repo or to memory without an `AskUserQuestion` approval) is **preserved**. The SKILL.md
frontmatter:3 and the :18-20 block were updated in lockstep with this addendum so the surface
and the doctrine agree.

## What stays rejected (would need a superseding ADR)

The entire ECC apply half: the self-launched observer daemon, headless "do not ask" writes,
the ≥0.7 auto-inject into session context, auto-promotion at a confidence threshold, `/evolve`
self-writing skill/agent files, and the `ecc2` cron + auto-merge daemon. These are L4 /
model-as-gate and remain out of scope by design (ADR 0002 "Rejected alternatives").
