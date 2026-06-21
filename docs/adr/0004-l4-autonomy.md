# ADR 0004: L4 self-driving harness — autonomy within the cage floor

- **Status**: **PROPOSED (draft, not accepted, not implemented)** — supersedes the *bounded-autonomy
  architecture* of [ADR 0003](0003-l3-bounded-autonomy.md) and relaxes the *principle* of
  [ADR 0002](0002-autonomy-invariant.md). Neither prior ADR is deleted; both remain the record of
  their eras. This ADR does not take effect until the owner flips it to **Accepted** and the
  machinery ships behind the hardening-before-enable rule below.
- **Date**: 2026-06-22
- **Decider**: Owner
- **Basis**: **telos, NOT capability.** (See §"The basis must be telos.")

## Context

ADR 0002 fixed **L2** (human gate per mutation) and called it irreversible "on a capability
argument." ADR 0003 superseded the *architecture* (not the principle) to add **L3** — a bounded,
human-launched, push-gated unattended loop. Under L3 the human already steps out of the loop
*during* a run; only two touchpoints remain: **Gate 1** (human launches) and **Gate 2** (human
reviews before push), with a *computational* in-loop gate (the gauntlet, never a model).

The owner now wants the harness to **self-drive** — to improve itself with the human out of *every*
per-run loop, matching the ECC continuous-learning flywheel kbg studied and previously rejected
([passive-learning-capture-design.md §2](../research/passive-learning-capture-design.md)). This is a
**telos change**, taken **after an explicit adversarial red-team** (recorded in §"Red-team") and
against an explicit recommendation to stage it. The owner chose the full move, eyes open. Per the
ADR-0003 mechanism, the autonomy ratchet turns only by a deliberate, human-authored, recorded
decision — this document is that decision.

> **Two different "L"s** (unchanged from ADR 0003): this is **autonomy level** L4, unrelated to the
> CLAUDE.md **context tiers** L1/L2/L3.

## Decision

Adopt **L4** — the four relaxations the owner selected, **each retained behind the irreducible cage
floor (§"The floor")**. L4 is gated behind a new opt-in flag, **`KBG_AUTONOMY_L4=1` (default OFF)**;
with it unset the harness behaves exactly as the L3/L2 record describes. (The flag stays the
computational, human-only, per-environment authorization signal — see ADR 0003 §"why an env var.")

| # | Relaxation | Replaces (L3) | ECC analogue |
|---|---|---|---|
| 1 | **Self-launch** — the loop starts on a schedule / event, no human Gate 1 | human launches `--auto` | `observe.sh` → `observer-loop` daemon + `daemon.rs` cron |
| 2 | **Auto-push / auto-merge** — the loop ships its batch, no human Gate 2 | human reviews then pushes | `maybe_auto_merge_ready_worktrees` |
| 3 | **Model-as-gate** — an LLM "good enough" verdict can stand in for the gauntlet | computational gauntlet only | confidence ≥0.7 "Auto-approved" |
| 4 | **Auto-apply / auto-inject** — headless writes + learnings injected each session without review | `kbg:learn` AskUserQuestion gate | `session-start.js` auto-injects ≥0.7 |

## The floor (irreducible — retained even under L4)

The owner selected the four relaxations above. The owner did **not** select removing the **cage**,
so it is **retained as the one irreducible brake**:

1. **Cage denylist (`scripts/l3-cage.txt`) stays enforced at pre-Act time.** The loop may never edit
   its own safety surface: the gates, the gauntlet, the audit, the doctrine, `.git/config`,
   **and the cage denylist + guard themselves**. An L4 loop may auto-improve the *non-safety* surface
   (skills, agents, docs, non-cage scripts) fully unattended, but it **cannot disable its own brakes
   or rewrite its governing ADRs.** This is the line between "aggressive self-improvement" and "no
   brakes at all." Removing the cage is a **separate, strongly-discouraged** future decision (it would
   make a runaway genuinely unrecoverable) and would require its own superseding ADR.
2. **Human kill-switch (computational, never a model).** The human can always stop L4: `KBG_AUTONOMY_L4=0`
   / a kill-file / removing the schedule. The stop condition is never delegated to the model.
3. **Per-cycle reversibility tags.** The loop tags before each cycle so a human can still `git reset`
   the local history; note this does **not** undo what relaxation #2 already pushed to `origin`.

**Net shape:** *maximal autonomy bounded by the cage.* The blast radius of any single bad cycle is
capped at the non-safety surface — recoverable from git — while the safety gates stay intact to catch
the next cycle.

## The basis must be telos

ADR 0002 foreclosed reopening this "on a capability argument" — i.e. *not* because models improved.
This ADR honors that: the justification on record is **"the owner wants a self-driving harness and
accepts that it may ship a bad change or damage its own non-safety surface,"** NOT "the model is good
enough now." If the real reason is the latter, this ADR is invalid and L3 stands.

## Red-team (recorded — risks accepted, not refuted)

A hard adversarial pass was run before this decision; the owner accepted these risks:

1. **"Green ≠ safe" — proven the same day.** The L3 machinery shipped "gauntlet-green" yet had **two
   blocking defects** found only by a *human* live dry-run (2026-06-22, see ADR 0003 note + CHANGELOG
   0.3.10). Under L4 (#1 self-launch, no human run) the next such defect **ships and propagates
   unattended.** Accepted.
2. **#2 + #3 = the LLM-judge-circularity the harness's own doctrine forbids.** Generator judges itself
   (#3) and ships its own verdict (#2) — the single-model failure mode the entire "inferential-FB is
   advisory-only" design exists to prevent (CLAUDE.md §LLM-judge-circularity). Accepted.
3. **Reversibility collapse + cross-repo blast radius.** #1+#2 mean a bad change self-launches and
   self-ships before the human sees it. ADR 0005 could revert the *policy* but not the *damage*. The
   harness gates security on the owner's **other** repos (secret-scan, dangerous-git, db-write); the
   cage floor (§"The floor") is what keeps an L4 loop from loosening those — which is why the cage is
   non-negotiable here. Accepted.

**Steelman (why this is a legitimate owner call):** single-author personal harness; worst case within
the cage floor is "rebuild the non-safety surface from git history." That genuinely lowers the stakes
versus a product or a team tool. It is the owner's tool and the owner's risk to take.

## What this inverts (existing invariants that change)

Accepting this ADR requires reworking — **not** silently — the following, each currently load-bearing:

- **audit #32** (recursive-improve `disable-model-invocation: true`, model-can't-self-start) — #1
  self-launch contradicts it; #32 must be redesigned, not deleted, to still forbid self-start *outside*
  an authorized L4 run.
- **`l3-push-gate.sh`** (Gate 2) — #2 removes it for L4 runs; it must stay active for non-L4 sessions.
- **`_lib.sh` L3 immunity** — extends to L4.
- **audit #43–#47** (cage completeness, no-permissionDecision capture, confidence-never-gates) — #3/#4
  invert #47's "confidence never gates"; #43 (cage completeness) becomes **more** load-bearing, not less.
- **CLAUDE.md "Deliberate non-goals"** (`/loop`, `CronCreate`, model-as-gate, L4) — #1 needs a
  self-launch primitive that section currently forbids; the section must be rewritten in lockstep.

## Implementation (separate, staged, NOT done by accepting this ADR)

This ADR is the **decision**, not the build. Even at L4, the **hardening-before-enable** rule from
ADR 0003 holds: the entire machinery (self-launch trigger, auto-push path, model-gate, auto-inject,
the retained cage + kill-switch + every reworked audit check + tests) must be committed and
gauntlet-green **before** the first `KBG_AUTONOMY_L4=1` run. Given red-team point #1, the owner is
**still advised** to bring the four relaxations up one at a time behind the flag, even though the
decision is "all four" — so a misbehaving loop is caught before it is shipping unattended.

## Reversibility of this ADR

Reversible by the same mechanism that created it: a human-authored **ADR 0005** superseding this one.
It **cannot** be reached or reverted by a flag flip, and — critically — **the L4 loop itself can never
author, edit, or accept its successor ADR** (the cage forbids `docs/adr/**`). The ratchet turns only
by deliberate human decision. This is the property that keeps L4 from becoming self-perpetuating.

## Open sub-decision (for the owner, before Accept)

- **Default state of `KBG_AUTONOMY_L4`** — recommended **OFF** (opt-in), like L3. Default-ON would
  arm self-launch in every environment the plugin loads, including the owner's employer repos.
- **The floor** — this draft *retains the cage*. Confirm, or open a separate ADR to remove it (not
  recommended).
