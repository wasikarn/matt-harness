# ADR 0005: L5 — auto-push/auto-merge (the human leaves the push loop)

- **Status**: **Accepted (telos decision recorded 2026-06-22) + IMPLEMENTED 2026-06-23 (Slice 4, issue
  #35, shipped gauntlet-green on `develop`; `KBG_AUTONOMY` still OFF by default — flag-OFF byte-identical
  to L2/L3/L4; enable still gated by §Acceptance criteria).** This ADR re-adds **relaxation #2 (auto-push
  / auto-merge)** that [ADR 0004](0004-l4-autonomy.md) dropped — the single touchpoint (Gate 2, the human
  push review) that ADR 0004 kept "permanently." It **supersedes ADR 0004's core sub-decision** ("keep the
  push gate permanently") and turns the autonomy ratchet one more notch. Per ADR 0004 §Reversibility, this
  was reached only by a deliberate, human-authored, recorded decision (owner, 2026-06-22). **Accepting
  records the destination only; it does NOT enable auto-push** — enable stays blocked until L4 ships and
  meets ADR 0004's i/ii/iii preconditions (§Sub-decisions, §Acceptance criteria).
- **Date**: 2026-06-22 (Accepted)
- **Decider**: Owner
- **Basis**: **telos, NOT capability** (inherited from ADR 0004 §"The basis must be telos").
- **Supersedes**: ADR 0004's sub-decision "Auto-push (#2) — keep the push gate permanently." Everything
  else in ADR 0004 (cage floor, kill-switch, cumulative cap, reversibility tags, the #1/#3/#4 relaxations,
  hardening-before-enable) is **retained unchanged**. ADR 0002/0003 remain the record of their eras.

## Context

Under ADR 0004 (L4, Accepted 2026-06-22) the harness self-launches (#1), self-judges via a veto-only
model gate (#3), and self-applies learnings (#4) — but a human reviews **every batch at Gate 2 before it
reaches `origin`.** The owner has now asked for the harness to match ECC **completely**, including ECC's
stage 5: auto-merge, with the human out of the push loop entirely.

This is the one move ADR 0004 explicitly held back and named *its own successor* for. Two passages in
ADR 0004 anticipate this document:

1. **§Sub-decisions → "If auto-push is ever revisited (a future ADR 0005 — *not* a flag flip)":** it sets
   three preconditions — **(i)** #1/#3/#4 have run unattended for **N cycles with zero bad ships**, **(ii)**
   F1/F2/F3 closed, **(iii)** the cumulative cap exists. *"Until then the gate stays. Dropping #2 is the
   reversible default; re-adding it is the one-way door, so it takes a deliberate superseding decision."*
2. **§Exit condition:** ADR 0004 committed the owner to author *the reverting* ADR 0005 if L4 ever shipped
   an unreviewed bad change. This ADR moves in the **opposite** direction — so it must also rewrite that
   exit condition, because under auto-push "one bad ship" is no longer the trip-wire (it becomes expected).

**The honest state today:** **none** of ADR 0004's three preconditions is met. No L4 machinery is built
(Slices 0–3 unstarted), zero unattended cycles have run, F1/F2/F3 are open, no cumulative cap exists. So
this proposal cannot honestly claim the bar ADR 0004 set for it. It therefore separates **two gates even
more sharply than ADR 0004 did**: *Accepting the telos* (the owner decides "yes, I want auto-push as the
end state") vs *enabling the machinery* (which stays blocked until ADR 0004's i/ii/iii are actually met —
see §Acceptance criteria). Accepting this ADR records the destination; it does not shorten the road.

> **Two different "L"s** (unchanged): this is **autonomy level** L5, unrelated to the CLAUDE.md
> **context tiers** L1/L2/L3.

## Decision (proposed)

Adopt **relaxation #2 (auto-push / auto-merge)** as **autonomy level L5**, on top of L4's #1+#3+#4, behind
the **single opt-in arming key `KBG_AUTONOMY=1` (default unset/`0` = OFF)** — *not* a per-level
`KBG_AUTONOMY_L5` key. The harness uses **one** on/off autonomy key; **which** capabilities an armed run
has is determined by the **committed slice code**, not by the key's value: pre-Slice-4 code denies at
Gate 2 (L4 behaviour), Slice-4 code auto-pushes on green (L5 behaviour). So "L5" names the
*committed-code era*, not a key value. (The per-level `KBG_AUTONOMY_L3/L4` keys collapse into this one at
Slice 0 — see the key-encoding note in ADR 0003/0004 and design §5 F1.) With `KBG_AUTONOMY` unset,
behaviour is exactly the L4/L3/L2 record — Gate 2 still denies the push.

**The crux — what replaces the human at Gate 2.** ADR 0004 §Red-team #2 made Gate 2 *load-bearing*: it is
the **independent checker** that backstops the model-as-gate (#3) circularity. Remove the human and
something must take that role, or L5 collapses into "the model ships its own verdict" — the exact
single-model failure the whole harness forbids (CLAUDE.md §LLM-judge-circularity). The proposed answer
follows **ECC's own design**: ECC's auto-merge (stage 5) is gated by a **computational** readiness check
(conflict-free git state-machine — `daemon.rs`), *not* by the model; ECC's model-as-gate lives at *inject*
(stage 3), not at *merge*. So:

> **L5 auto-pushes a batch only when the full computational gauntlet is green.** The independent ship-gate
> becomes the **gauntlet** (deterministic), not the model and not a human. The model (#3) stays
> **veto-only** — it can force an extra rollback, it can **never** authorize a ship. The autonomy
> invariant's deepest rule ("the gate that authorizes a mutation/ship stays computational, never a model")
> is **preserved** — the human is removed, the computational gate is not.

| # | Relaxation | L4 state | L5 change |
|---|---|---|---|
| 1 | Self-launch | adopted | unchanged |
| 2 | **Auto-push / auto-merge** | **dropped (Gate 2 kept)** | **adopted — push when the gauntlet is green; no human review** |
| 3 | Model-as-gate | veto-only | **unchanged — stays veto-only; gains NO ship authority** |
| 4 | Auto-apply / auto-inject | adopted | unchanged |

## The floor (retained from ADR 0004 — plus one addition)

ADR 0004's entire floor is **retained**: the cage (`scripts/l3-cage.txt`), the computational kill-switch,
per-cycle reversibility tags, the cumulative ceiling (R4), and `docs/adr/**` in the cage so **the loop can
never author or accept its own successor ADR.** L5 adds one floor item and rewrites the push surface:

1. **Computational ship-gate (replaces Gate 2).** Auto-push fires **only** behind a passing
   `run-gauntlet.sh` (plugin-validate + audit 0C/0W incl. #43–#48 + critical-hooks + eval gate) on the
   always-computational path. A red gauntlet → no push, rollback. The model verdict is **not** in this
   gate's authorization path (veto-only, §Decision).
2. **Cross-repo backstop is now the only pre-`origin` check — so it moves before the push, not after.**
   ADR 0004 §10 specified a *post-push* tripwire (run #43–#47 against `origin/develop`). Under L4 that was a
   second line behind the human. Under L5 there is no human, so the cross-repo security-gate assertion
   (no loosening of secret-scan / dangerous-git / db-write) must run **as a pre-push CRIT inside the
   computational ship-gate**, blocking the push — not only as an after-the-fact detector. The
   *post*-push tripwire against `origin/develop` is **also** kept as the witness-outside-the-cage
   (exit-trigger detector; the cage cannot witness its own breach).
3. **`#44` push-gate inverts, not vanishes.** Audit #44 currently asserts Gate 2 denies an unreviewed
   push. Under L5 it must instead assert: a push is denied **unless** the computational ship-gate passed,
   and is **always** denied if the model verdict was the only thing green. The human-review override
   (`KBG_L3_REVIEW_DONE=1`) remains available but is **no longer required** for an L5 push.

**Net shape:** *maximal autonomy bounded by the cage, with the ship-gate kept computational and the human
removed from the push loop.* The cage still caps **which files** a bad cycle can touch (non-safety surface
only — it cannot loosen its own brakes or edit ADRs). What changes versus L4: a degraded **non-safety**
change that passes the gauntlet now reaches `origin` with **no human catch**. That is the whole telos and
the whole cost.

## The basis must be telos

Same honesty bar as ADR 0004: the justification on record is **"the owner wants a fully self-driving
harness and accepts that it will, eventually, auto-ship a bad-but-green change to `origin`,"** NOT "the
model / gauntlet is good enough now." ADR 0004 §Red-team #1 *proved the same day* that green ≠ safe — the
L3 machinery shipped gauntlet-green yet had two blocking defects a **human** caught in a live dry-run
(v0.3.10). Under L5 that class of defect auto-ships. If the real reason to adopt L5 is "I now trust green,"
this ADR is **invalid** and L4 stands. The valid reason is telos: the owner wants the human out of the push
loop and accepts the residual.

**Exit condition (rewritten for L5 — kept falsifiable per ADR 0002 §Gate-discipline).** Under auto-push,
"one bad ship" can no longer be the trip-wire (bad-but-green ships are the *accepted* residual). The owner
commits to treat **either** of the following as evidence L5 was the wrong call and a trigger to author the
reverting **ADR 0006**: (a) any L5 auto-ship that **loosened a cross-repo security gate** (secret-scan /
dangerous-git / db-write) — one event, not a band; or (b) any L5 auto-ship that required **more than a
single `git revert` to recover** (i.e. it propagated, was built upon, or escaped before catch). Routine
single-revert recoveries of a bad-but-green non-safety change are the *accepted cost*, not an exit signal —
otherwise the exit condition is un-falsifiable and L5 is a belief, not a decision.

## Red-team (residuals — accepted, not refuted)

1. **Green ≠ safe, now un-backstopped at push.** The defining residual. The gauntlet was green on v0.3.10
   with two blocking defects; a human caught them at the boundary L5 removes. Under L5 that auto-ships.
   *Mitigation, not elimination:* the computational ship-gate is the **full** gauntlet (not the model), the
   pre-push cross-repo CRIT blocks the worst class, and recovery is `git revert` + the post-push tripwire.
   Residual = a local-origin bad-but-green non-safety commit, single-revert recoverable. **The owner must
   accept this specific event will eventually happen** — it is the price of removing the human.
2. **Model-as-gate circularity.** *Addressed by design, not accepted:* #3 stays veto-only and gains no ship
   authority; the ship-gate is the deterministic gauntlet. The single-model loop never closes on itself
   because the authorizing check is computational. (This is *stronger* than ECC, whose merge is also
   computational but whose inject-gate model verdict is unbacked.)
3. **Cross-repo blast radius without a human.** *Mitigation:* cage blocks the loop editing those gates
   directly (retained); the cross-repo loosening assertion runs as a **pre-push** CRIT (§floor 2); the
   post-push tripwire is the outside-the-cage witness. Residual = the window between a slip the cage misses
   and the tripwire firing. Exit-condition (a) makes one such event a revert trigger.
4. **"Bad-but-green" accretion.** Many small bad-but-green ships could accrete faster than a human notices.
   *Mitigation:* R4's cumulative cap bounds cycles/window; the Gate-2 journal (ADR 0004 §10) becomes an
   **auto-ship journal** reviewed at the quarterly decay sweep so a degradation streak is observable.

**Steelman (why this is a legitimate owner call):** single-author personal harness; the cage confines the
worst case to the non-safety surface, and every L5 ship is `git`-recoverable from history. It is the
owner's tool and the owner's risk. The same steelman that justified L4 justifies L5 *if and only if* the
owner genuinely accepts residual #1 as a when-not-if.

## What this inverts (beyond ADR 0004's already-listed reworks)

Accepting this ADR requires reworking — **not** silently:

- **ADR 0004 §Decision row 2 + §Sub-decisions "Auto-push kept permanently"** — superseded; #2 is adopted.
  ADR 0004's preconditions (i/ii/iii) are **carried forward as the enable-gate**, not waived (§Acceptance).
- **ADR 0004 §Exit condition** — replaced by the L5 exit condition above (single-bad-ship is no longer the
  trigger; cross-repo-loosening or >single-revert is).
- **`l3-push-gate.sh` / audit #44** — invert from "deny unless human-reviewed" to "deny unless the
  computational ship-gate passed" under L5 (§floor 3). The human override survives but is not required.
- **The cross-repo tripwire (ADR 0004 §10 / design §10)** — promoted from post-push detector to **pre-push
  blocking CRIT** *and* kept as the post-push witness (§floor 2).
- **CLAUDE.md "Deliberate non-goals" + "autonomy invariant"** — currently say auto-push/auto-merge is out
  of scope and "L4 (no human gate at all)" is forbidden. Rewrite in lockstep: the human gate at *push* is
  removed; the **computational** ship-gate and the cage replace it; "no human gate at all" is now true only
  for the push loop, false for the cage/ADR boundary (the loop still cannot edit its brakes or its ADRs).
- **`docs/research/l4-machinery-design.md` title + §9** — the design is titled "L4-push-gated"; a Slice 4
  (auto-push, computational ship-gate) must be appended, staged **after** Slices 0–3 ship and run clean.

## Sub-decisions (resolved to the recommended values — pending owner Accept)

1. **Ship-gate authority — RESOLVED: computational (gauntlet-gated auto-push).** The model stays
   veto-only; the **gauntlet** authorizes the ship. ECC-faithful (ECC merges on a computational readiness
   check) and preserves the "ship-gate stays computational, never a model" invariant. **Rejected
   alternative (on record):** *model-gated auto-push* — letting #3's "good enough" verdict authorize the
   ship with no computational backstop; **more aggressive than ECC** and breaks the invariant. Not adopted
   unless a future ADR explicitly overrides.
2. **Enable-gate preconditions (ADR 0004 i/ii/iii) — RESOLVED: honor, not waive.** L5 cannot enable until
   L4 has shipped and run unattended for **N ≥ 20 cycles across ≥ 2 weeks with zero bad ships**, F1/F2/F3
   are closed, and the cumulative cap exists. Accepting the *telos* now is fine; **enabling** before these
   are met is forbidden — it would contradict the bar ADR 0004 set one notch below. No waiver taken.
3. **Default state of `KBG_AUTONOMY` — RESOLVED: OFF (unset/`0`), opt-in like L3/L4.** Default-ON would arm
   autonomy in every environment the plugin loads, including employer repos. Opt-in keeps it dormant until
   the owner sets `KBG_AUTONOMY=1` in a chosen environment.

## Acceptance criteria (PROPOSED → Accepted → Enabled — three gates)

- **To Accept the *telos*** (owner flips Status to Accepted): the three sub-decisions above are resolved;
  this ADR carries the reworked-invariant list, the rewritten exit condition, and the red-team. No code is
  required to Accept. Accepting records the destination only — **it does not enable auto-push.**
- **To *enable* the machinery** (first armed `KBG_AUTONOMY=1` auto-push run), all must hold, gauntlet-green
  under the flag (the v0.3.10 lesson — measure green *with* the flag set):
  1. **Flag OFF** (`KBG_AUTONOMY` unset/`0`) → byte-identical to the L4/L3/L2 record; no push path beyond Gate 2.
  2. **ADR 0004's i/ii/iii actually met** (§sub-decision 2) unless explicitly waived: L4 shipped, ran N
     clean cycles, F1/F2/F3 closed, cumulative cap exists.
  3. **The computational ship-gate is built and tested**: a green gauntlet auto-pushes; a **red** gauntlet
     **never** pushes; a green-only-by-model-verdict (gauntlet red) **never** pushes; the pre-push
     cross-repo CRIT blocks a simulated security-gate loosening; the post-push tripwire still fires as the
     outside-the-cage witness. Fail-closed: a ship-gate shell-out error → no push.
  4. **Reworked audits assert the L5 contract**: #44 inverted (deny unless gauntlet-passed; never on model
     verdict alone), #48 reads the single `KBG_AUTONOMY` key, the cage still CRIT-green, #32 unchanged (the
     OS/launcher self-starts, not the model — auto-push does not touch that assertion).

## Reversibility of this ADR

Reversible by the same mechanism that created it: a human-authored **ADR 0006** superseding this one. It
**cannot** be reached or reverted by a flag flip, and **the L5 loop itself can never author, edit, or
accept its successor ADR** — the cage forbids `docs/adr/**` (retained from ADR 0004 §floor). The ratchet
turns only by deliberate human decision; this is the property that keeps L5 from becoming
self-perpetuating even with the human out of the push loop.
