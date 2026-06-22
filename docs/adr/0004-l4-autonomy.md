# ADR 0004: L4 self-driving harness — autonomy within the cage floor

- **Status**: **Accepted (decision recorded 2026-06-22; NOT YET IMPLEMENTED — no L4 machinery exists,
  all flags OFF)** — supersedes the *bounded-autonomy architecture* of
  [ADR 0003](0003-l3-bounded-autonomy.md) and relaxes the *principle* of
  [ADR 0002](0002-autonomy-invariant.md). Neither prior ADR is deleted; both remain the record of
  their eras. **Accepting the decision and enabling the machinery are separate gates** (see
  §"Acceptance criteria"): this Accept records the telos decision only; nothing self-drives until the
  full machinery ships gauntlet-green behind the hardening-before-enable rule and the owner sets
  `KBG_AUTONOMY_L4=1`.
- **Date**: 2026-06-22 (Accepted)
- **Decider**: Owner
- **Basis**: **telos, NOT capability.** (See §"The basis must be telos.")

## Context

ADR 0002 fixed **L2** (human gate per mutation) and called it irreversible "on a capability
argument." ADR 0003 superseded the *architecture* (not the principle) to add **L3** — a bounded,
human-launched, push-gated unattended loop. Under L3 the human already steps out of the loop
*during* a run; only two touchpoints remain: **Gate 1** (human launches) and **Gate 2** (human
reviews before push), with a *computational* in-loop gate (the gauntlet, never a model).

The owner now wants the harness to **self-drive** — to improve itself with the human out of the
*launch* and *per-mutation* loops, matching the ECC continuous-learning flywheel kbg studied and
previously rejected ([passive-learning-capture-design.md §2](../research/passive-learning-capture-design.md)).
This is a **telos change**, taken **after an explicit adversarial red-team** (recorded in §"Red-team")
and a multi-agent review/audit of this very draft. The owner first chose the full move, then — given
the review's findings — **narrowed it: drop auto-push (#2), keep the human push gate (Gate 2)
permanently** (decided 2026-06-22; see §"Open sub-decision"). The human stays out of every loop
*except* the one irreversible, outward boundary. Per the ADR-0003 mechanism, the autonomy ratchet turns
only by a deliberate, human-authored, recorded decision — this document is that decision.

> **Two different "L"s** (unchanged from ADR 0003): this is **autonomy level** L4, unrelated to the
> CLAUDE.md **context tiers** L1/L2/L3.

## Decision

Adopt **L4 (push-gated)** — **three** relaxations (#1, #3, #4), **each retained behind the irreducible
cage floor (§"The floor")**, with **auto-push (#2) dropped: the human push gate (Gate 2) is kept
permanently.** The human is out of the *launch* and *per-mutation* loops but reviews every batch before
it reaches `origin`. L4 is gated behind a new opt-in flag, **`KBG_AUTONOMY_L4=1` (default OFF)**; with it
unset the harness behaves exactly as the L3/L2 record describes. (The flag stays the computational,
human-only, per-environment authorization signal — see ADR 0003 §"why an env var.")

| # | Relaxation | Replaces (L3) | ECC analogue |
|---|---|---|---|
| 1 | **Self-launch** — the loop starts on a schedule / event, no human Gate 1 | human launches `--auto` | `observe.sh` → `observer-loop` daemon + `daemon.rs` cron |
| 2 | ~~**Auto-push / auto-merge**~~ — **DROPPED (2026-06-22).** Gate 2 kept permanently; the loop commits locally, a human reviews before `origin` | (Gate 2 retained from L3) | `maybe_auto_merge_ready_worktrees` (not adopted) |
| 3 | **Model-as-gate** — an LLM "good enough" verdict can stand in for the gauntlet | computational gauntlet only | confidence ≥0.7 "Auto-approved" |
| 4 | **Auto-apply / auto-inject** — headless writes + learnings injected each session without review | `kbg:learn` AskUserQuestion gate | `session-start.js` auto-injects ≥0.7 |

## The floor (irreducible — retained even under L4)

The owner adopted three of the four relaxations above (auto-push #2 dropped). The owner did **not**
select removing the **cage**, so it is **retained as the one irreducible brake** — alongside the kept
push gate (Gate 2):

1. **Cage denylist (`scripts/l3-cage.txt`) stays enforced at pre-Act time.** The loop may never edit
   its own safety surface: the gates, the gauntlet, the audit, the doctrine, `.git/config` +
   `.git/hooks/**` + `git-hooks/**` (the gauntlet wiring), **and the cage denylist + guard themselves**.
   An L4 loop may auto-improve the *non-safety* surface (skills, agents, docs, non-cage scripts) fully
   unattended, but it **cannot disable its own brakes or rewrite its governing ADRs.** This is the line
   between "aggressive self-improvement" and "no brakes at all." Removing the cage is a **separate,
   strongly-discouraged** future decision (it would make a runaway genuinely unrecoverable) and would
   require its own superseding ADR.

   Two surfaces the L3 cage does **not** yet cover must be added before L4 enable, because under L4 the
   loop can otherwise weaken what judges it (no human Gate 2 catches it):
   - **The gauntlet-grading corpus** — `eval/regressions/**` and `tests/evals/**`. The gauntlet grades
     the loop against these fixtures; if they are editable, a bad cycle can rewrite the fixture to
     ratify broken behavior and self-pass. (Audit-finding F2.)
   - **The self-launch scheduler config** — the canonical schedule/daemon path that powers relaxation #1
     (defined before implementation). If it is editable, a cycle can install a second persistent entry
     that survives the kill-switch. (Audit-finding F3.)

   Both must land in `scripts/l3-cage.txt` **and** the `CAGE_ANCHORS` heredoc in audit #43 so
   cage-completeness is machine-verified.

   **The cage/governance audit checks run every cycle, computationally — relaxation #3 may NOT bypass
   them.** The model "good enough" verdict (#3) may stand in only for the *quality* portion of the
   gauntlet; audit #43–#47 (cage completeness + the autonomy-invariant checks) must run on the
   always-computational path each cycle regardless of #3, or the cage cannot detect its own drift at
   the exact cadence the floor leans on. (Audit-finding R3.)
2. **Human kill-switch (computational, never a model).** The human can always stop L4. The three
   mechanisms differ in latency granularity, and the floor must say so: `KBG_AUTONOMY_L4=0` and removing
   the schedule take effect at the **next cycle boundary** (the per-cycle guard re-reads the
   environment), while a **kill-file** re-checked at finer points is the fastest brake against an
   in-flight cycle. Crucially, because relaxation #1 self-launches from a persistent scheduler, the
   env-var alone is **not** sufficient: stopping a self-launching loop requires **removing the scheduler
   entry AND setting the flag to 0** — the env-var stops the current process, the schedule removal stops
   the next launch. The stop condition is never delegated to the model.
3. **Per-cycle reversibility tags.** The loop tags before each cycle so a human can `git reset` the
   local history. With #2 dropped, nothing reaches `origin` unreviewed, so a local reset **fully**
   recovers a bad cycle — the recoverability is real, not partial.
4. **A computational cumulative ceiling for the self-launching case.** L3's per-run caps
   (`--max-runs=3`, `--max-duration`) bound a *single human-launched run*; under relaxation #1 the
   *number of runs* is itself unbounded (one per schedule tick), so per-run caps do **not** bound the
   sequence. The floor must add a locally-observable cumulative cap — run-frequency per window and/or
   cumulative-cycle and/or wall-clock-per-window — so the worst case is "N self-launched cycles" with
   **N named**, not an open-ended accretion. (Audit-finding R4.)

**Net shape:** *maximal autonomy bounded by the cage, with the human kept at the one irreversible
boundary.* The cage caps **which files** a bad cycle can touch to the non-safety surface; the retained
push gate (Gate 2) keeps every change **local and `git reset`-able until a human reviews it.** So
"recoverable from git" is now **true** — a bad cycle is bounded to the non-safety surface *and*
reversible, because nothing reaches `origin` (or propagates cross-repo) without a human. This is the
~90%-of-the-telos / ~10%-of-the-irreversibility shape: the loop self-launches, self-judges, and
self-improves unattended; the human reviews the batch before it leaves the machine. **The human push
review is now load-bearing** — it is the independent check that backstops the model-as-gate (#3), so it
must be a real review, not a rubber-stamp.

## The basis must be telos

ADR 0002 foreclosed reopening this "on a capability argument" — i.e. *not* because models improved.
This ADR honors that: the justification on record is **"the owner wants a self-driving harness and
accepts that it may ship a bad change or damage its own non-safety surface,"** NOT "the model is good
enough now." If the real reason is the latter, this ADR is invalid and L3 stands.

**Exit condition (so "telos" is a basis, not an un-falsifiable shield).** A value choice with no exit
condition is a belief, not a decision (ADR 0002 §Gate-discipline applied in mirror). The owner commits
to treat the following as evidence that L4 was the wrong call and a trigger to author the reverting
**ADR 0005**: *any* unreviewed bad change reaching `origin` that a human would have caught at Gate 2, or
*any* loosening of a cross-repo security gate (secret-scan / dangerous-git / db-write) slipping past the
cage. One such event is the signal — not a tolerance band.

## Red-team (recorded — risks accepted, not refuted)

A hard adversarial pass was run before this decision; the owner accepted these risks:

1. **"Green ≠ safe" — proven the same day.** The L3 machinery shipped "gauntlet-green" yet had **two
   blocking defects** found only by a *human* live dry-run (2026-06-22, see ADR 0003 note + CHANGELOG
   0.3.10). Under L4 the next such defect would be **committed locally** by an unattended run.
   *Resolution (drop #2):* it no longer **ships** unattended — the retained push gate holds it for human
   review at Gate 2; residual exposure is a local, git-recoverable commit, and the human review must
   actually catch it (so Gate 2 review is load-bearing, not a rubber-stamp).
2. **#3 model-as-gate = LLM-judge-circularity if it stands alone.** A same-model generator+judge has
   shared blind spots — the single-model failure mode the "inferential-FB is advisory-only" design
   exists to prevent (CLAUDE.md §LLM-judge-circularity). *Resolution (drop #2):* with auto-push gone the
   model verdict no longer **ships itself** — the human at Gate 2 is the **independent checker** the
   circularity removed. #3 now weakens only the *in-loop* quality gate (what gets committed locally); the
   human push review is the backstop, and #43–#47 still run computationally every cycle regardless of #3
   (§The floor).
3. **Reversibility collapse + cross-repo blast radius.** *Resolution (drop #2):* the collapse was driven
   by #1+**#2** — self-launch *and* self-ship. With #2 dropped a bad change self-launches but stays
   **local** and gated at push; it cannot reach `origin` or propagate to the owner's **other** repos
   (secret-scan, dangerous-git, db-write) unreviewed. The cage still blocks the loop from loosening
   those gates directly; the push gate blocks shipping a degraded non-safety change unreviewed. Residual
   is bounded to a local, git-recoverable tree.

**Steelman (why this is a legitimate owner call):** single-author personal harness; worst case within
the cage floor is "rebuild the non-safety surface from git history." That genuinely lowers the stakes
versus a product or a team tool. It is the owner's tool and the owner's risk to take.

## What this inverts (existing invariants that change)

Accepting this ADR requires reworking — **not** silently — the following, each currently load-bearing:

- **audit #32** (recursive-improve `disable-model-invocation: true`, model-can't-self-start) — #1
  self-launch contradicts it; #32 must be redesigned, not deleted, to still forbid self-start *outside*
  an authorized L4 run.
- **`l3-push-gate.sh` + `_lib.sh` L3 immunity + `l3-loop-guard.py` TAMPER_VARS — all are scoped to the
  `KBG_AUTONOMY_L3` flag and go *inert* under an L4 flag (audit-finding F1, the highest-severity gap).**
  The build must extend all three to fire on `L3 OR L4` and add `KBG_AUTONOMY_L4` to `TAMPER_VARS`, so an
  L4 run cannot disarm gates via `CLAUDE_HOOK_PROFILE=off` or push unreviewed. **Because #2 is dropped,
  there is NO auto-push carve-out:** the push gate (Gate 2) simply **also fires under L4**, denying
  `git push` until a human marks the batch reviewed — exactly as under L3. A new audit check (#48+) must
  assert these gates fire under the L4 flag.
- **audit #43–#47** — these are five *distinct* checks, not one concern: #43 cage completeness, #44
  push-gate + git-wiring, #45 reviewer read-only (maker≠checker), #46 sync-seam, #47 capture
  confidence-never-gates. **#44 (push-gate) extends to fire under L4 — the gate is retained, not removed
  (#2 dropped);** #4 inverts **#47** ("confidence never gates") for the auto-inject case; #45 becomes
  materially relevant (reviewers run unattended inside the loop); and **#43 must become
  computational-every-cycle, not gauntlet-only (see §The floor item 1) — it is more load-bearing under
  L4, so it must fire *more* often, not less.**
- **CLAUDE.md "Deliberate non-goals"** (`/loop`, `CronCreate`, model-as-gate, L4) — #1 needs a
  self-launch primitive that section currently forbids; the section must be rewritten in lockstep.

## Implementation (separate, staged, NOT done by accepting this ADR)

This ADR is the **decision**, not the build. Even at L4, the **hardening-before-enable** rule from
ADR 0003 holds: the entire machinery (self-launch trigger, model-gate, auto-inject, the retained cage +
push gate + kill-switch + every reworked audit check + tests) must be committed and gauntlet-green
**before** the first `KBG_AUTONOMY_L4=1` run. There is **no auto-push path** (#2 dropped). Given
red-team point #1, the owner is **still advised** to bring the three relaxations up one at a time behind
the flag — so a misbehaving loop is caught before it runs unattended.

**Recommended staging order** (lowest blast radius first): (1) **#4 auto-inject** — session-scoped,
nothing leaves the machine, half-built already (`learn-capture` exists); (2) **#3 model-as-gate**
trialed on one low-stakes skill, *with the gauntlet still running underneath*; (3) **#1 self-launch**
with the push gate (Gate 2) active. The push gate stays on at every stage — auto-push (#2) is dropped,
not deferred.

## Acceptance criteria (Verification — what makes PROPOSED → Accepted, mirroring ADR 0003 §Verification)

The Accept act and the first enable are **separate gates**:

- **To Accept the *decision*** (owner flips Status): the three sub-decisions below are all resolved
  (auto-push #2 dropped; default `KBG_AUTONOMY_L4` OFF; cage retained); the ADR text carries the
  reworked-invariant list, the exit condition, and this section. No code is required to Accept —
  **done 2026-06-22.**
- **To *enable* the machinery** (first `KBG_AUTONOMY_L4=1` run), per hardening-before-enable, all must
  hold and be **gauntlet-green under the flag** (the v0.3.10 lesson: measure green *with* the flag set,
  not only flag-OFF):
  1. **Flag OFF** → behavior byte-identical to the L3/L2 record; the self-launch primitive inert.
  2. **Flag ON dry-run** → each enabled relaxation's observable fires and journals a run-id:
     self-launch fires only inside an authorized run; the push gate denies `git push` until a human
     marks the batch reviewed (auto-push dropped — no auto-ship path); the model-gate path is exercised;
     the auto-inject path is exercised; a cage-path Act still aborts at the pre-Act check; the
     kill-switch stops the loop.
  3. **Predecessor fixes committed**: F1 (push gate + `_lib` immunity + `TAMPER_VARS` fire under L4 —
     deny, no carve-out), F2/F3 (cage + `CAGE_ANCHORS` extended), R3 (audit #43–#47 on the
     always-computational path), R4 (cumulative cap).
  4. **Reworked audit checks assert the L4 contract**: redesigned #32 (forbids self-start *outside* an
     authorized L4 run), the inverse of #47 (confidence may order an auto-keep only *inside* an L4 run),
     #43 cage-completeness CRIT-green with the new anchors, and the new #48+ (gates fire under L4).

## Reversibility of this ADR

Reversible by the same mechanism that created it: a human-authored **ADR 0005** superseding this one.
It **cannot** be reached or reverted by a flag flip, and — critically — **the L4 loop itself can never
author, edit, or accept its successor ADR** (the cage forbids `docs/adr/**`). The ratchet turns only
by deliberate human decision. This is the property that keeps L4 from becoming self-perpetuating.

## Sub-decisions (all RESOLVED 2026-06-22)

- **Auto-push (#2) — RESOLVED 2026-06-22: option (a), keep the push gate permanently (drop #2).** The
  owner chose to keep the human at the one irreversible, cross-repo boundary. L4 adopts #1 + #3 + #4; the
  loop self-launches, self-judges, and self-improves unattended, but a human reviews every batch before
  it reaches `origin`. This is ~90% of the telos at ~10% of the irreversibility, and it makes the
  "recoverable from git" guarantee true. The rejected shapes are kept on record: **(b)** stage #2
  dead-last; **(c)** all-four-at-once.
  - **If auto-push is ever revisited** (a future ADR 0005 — *not* a flag flip): the criterion is (i)
    #1/#3/#4 have run unattended for N cycles with zero bad ships, (ii) F1/F2/F3 closed, (iii) the
    cumulative cap exists. Until then the gate stays. Dropping #2 is the reversible default; re-adding it
    is the one-way door, so it takes a deliberate superseding decision, not a config change.
- **Default state of `KBG_AUTONOMY_L4` — RESOLVED 2026-06-22: OFF (opt-in), like L3.** Default-ON would
  arm self-launch in every environment the plugin loads, including the owner's employer repos; opt-in
  keeps L4 dormant until the owner sets `KBG_AUTONOMY_L4=1` in a chosen environment.
- **The floor — RESOLVED 2026-06-22: the cage is RETAINED.** Removing it would require its own
  superseding ADR (strongly discouraged — it would make a runaway genuinely unrecoverable).
