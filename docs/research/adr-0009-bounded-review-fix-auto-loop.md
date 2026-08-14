# ADR 0009 — Bounded review→fix auto-loop (the per-round "go" button)

> **Status:** 🟡 Proposed (Accepted-not-Implemented) — awaiting operator approval.
> This ADR supersedes **part** of ADR 0006. It does NOT ship until the operator
> approves it AND the implementation (the "go"-button change + its audit guard)
> lands. Until then the loop stays human-started per round (the current behavior).
> **Date:** 2026-08-14 · **Decider:** Operator · **Supersedes:** the "no model
> self-start" *expression* of ADR 0006, narrowly for the bounded review→fix loop.
> **Retains:** the maker≠checker *principle*, the computational merge-gate, the
> no-model-self-**launch** invariant (launchd/cron/`claude -p` self-start), and
> the "model confidence is never the auto-act signal" rule.

## Fresh-context review (2026-08-14)

Five fresh-context reviewers (doctrine-fidelity, steelman-against,
implementation-feasibility, bypass/incident, gate-sufficiency) read this ADR +
ADR 0006's sources independently. Verdicts:
- **Doctrine-fidelity:** HOLDS-WITH-CAVEATS — passes all 4 doctrine tests; "no
  model self-start" ambiguity is operator's to resolve.
- **Steelman-against:** SURVIVES-WITH-REWORK — the expression-vs-principle
  distinction is self-graded by the implementing session (the exact circularity
  the crux warns against). Operator must hear the steelman, not just the
  ADR's self-rebuttal.
- **Implementation-feasibility:** BUILDABLE-WITH-REWORK — the continue decision
  must move to a shell script (not SKILL.md prose) to make the audit guard
  mechanically enforceable + close the sync-seam.
- **Bypass/incident:** No bad-ship path found (merge gate holds both layers).
  But the ADR under-frames the real harm: compounding entanglement (not just
  burn) + trivial-diff clean-pass (latent bug → clean → merge on buggy diff).
- **Gate-sufficiency:** SUFFICIENT-WITH-CEILING — the gate alone is NOT
  sufficient. It catches cross-file regression + all-tiers-flat stalls, but
  misses same-file churn, same-file tier reclassification, cross-tier same-file
  whack-a-mole, rounds 1-2, Minor churn. The ADR's original Context claim that
  `stalled` catches whack-a-mole was WRONG for the same-file case. The ceiling
  does double duty (universal backstop, not just the human gate).

**Cross-ADR pass (2026-08-14, 2nd round — 4 reviewers reading ADRs 0001-0008
from git history, not just this ADR in isolation):** three framing corrections
landed. (1) The "proposed 4× / refused 4× / 4 reasons" setup was inflated —
decay-cadence records 3 refusal reasons for a *verifier-first runtime*, and "no
model self-start" is the principle those rest on, not a 4th standalone reason;
the 4 recurrences (memory `rgs-pushback-descope-2026-07-01`) were of a broader
"Reasoning Governance System" pattern, not 4 refusals of this loop. (2) The
"no model self-start is stated flatly" claim was true only of the *compressed*
doctrine (CLAUDE.md/decay-cadence) — the *source* ADR 0006 scopes it to
self-launch, which narrows the operator's open question (see below). (3) The
strongest surviving steelman: ADR 0006 stripped `--auto` and restored the
per-iteration human gate, and this ADR reverses that for review→fix — so refusal
#3 partially bites on the *shape* (L3's auto-continue) even though it does not
bite on the *ratchet identity* (no flag/notches/self-launch/auto-push). Also:
renumbered 0007→0009 to avoid collision with the retired `docs/adr/0007-ecc-parity-
ports` in git history; fixed `docs/agents/domain.md` generic-template example.

**The one thing the operator must resolve before acceptance:** how "no model
self-start" reads against its *source*, not just its compressed restatement. ADR
0006 — the ADR this one supersedes — **does not state "no model self-start"
flatly.** Its "What lives (preserved)" section scopes it explicitly to
self-launch: *"The model cannot self-start the improvement loop. (The launchd
self-start is gone with the L4 machinery; there is no OS-scheduler self-start
either now.)"* — a *process-lifecycle* scope (launchd/cron/detached self-start of
a loop from zero), not a per-round-continue scope. The *compressed* doctrine
(`CLAUDE.md` §Architecture, `harness-decay-cadence.md`) dropped that scoping and
does state it flatly; an operator reading only the current docs finds genuine
ambiguity, but an operator reading the source ADR does not — old 0006 forecloses
the launchd/cron reading directly, and per-round auto-continue within an
operator-started session is not self-start in 0006's sense.

This *narrows* the open question but does not fully close it: 0006's "new
principle" sentence ("there is no autonomy flag, no enforced maker≠checker
ship-gate, and no model self-start") is stated broadly, and 0006 did not merely
retire the flag — it **stripped `--auto` and restored the per-iteration human
gate**. So the residual question the operator must weigh is narrower than
"expression vs. blanket": it is whether **auto-continue bounded by a
deterministic stop + human ceiling, with no flag/ratchet/self-launch**, is a
re-arming of L3's retired auto-continue *shape* (which 0006 explicitly stripped)
or a separable loop behavior the ladder happened to include. The operator must
engage the steelman's strongest point (refusal #3 refused the *shape* "auto
retry/re-plan IS the ladder," not the stop; L3's shape was auto-continue within a
human-started session, and 0006 stripped it; the expression-vs-principle
distinction is self-graded by the implementing session) before moving this ADR
from Proposed to Accepted. Without that, the "Why this is not the 5th refusal"
table is the maker grading its own work — the exact circularity the crux exists to
prevent.

## Context

### What ADR 0006 retired and why

ADR 0006 retired the L2–L5 autonomy ladder (L3 bounded autonomy, L4 self-launch,
L5 auto-push) and codified the operating model (`CLAUDE.md` §Architecture): *deny
the irrecoverable set computationally, advise on the rest; the operator is the
authority at every irreversible boundary; no model self-start.* The retiring
crux (`agent-loop-verifier-crux.md`): *the gate is a verifier, the model is the
maker, and the maker can never grade its own work — "two optimists agreeing."*

The broader idea — a model-driven auto-loop / "reasoning governance runtime" —
recurred **4×** on a single day (2026-07-01), each a generic "Phase N" framework
spec (RAF/RGS/RVSEF/verifier-runtime) colliding with the retired L2–L5 ladder +
verifier-separation crux, and each de-scoped (memory `rgs-pushback-descope-
2026-07-01`). The 4th recurrence is the one recorded in
`docs/harness-decay-cadence.md` §"Refused extension: mandatory verification of
every reasoning event" — a "verifier-first runtime" generalizing deny-gates from
*irreversible actions* to *every reasoning event*. That record lists **3** refusal
reasons (not 4):

1. Classifying decision criticality / "verifying reasoning" at runtime needs an
   LLM doing the classifying (unverified reasoning gating reasoning — the model
   grading itself) or deterministic semantic understanding of free text (not
   buildable).
2. Confidence-based gating uses model self-report as the gate signal — same
   crux, "two optimists agreeing."
3. Mandatory-verify-everything + auto retry/re-plan/escalate is the L2–L5 ladder
   under a new name — retired by ADR 0006, do not re-arm.

**"No model self-start" is not a 4th standalone refusal reason** — it is the
underlying *principle* (the maker≠checker / no-self-launch invariant) the three
reasons above rest on, and the invariant ADR 0006 explicitly preserved. This
ADR's narrower proposal (bounded review→fix auto-continue) is a specific instance
the framework-level refusals addressed at full generality; the honest question is
whether the narrowing (one loop, deterministic stop, no flag/ratchet/self-launch)
escapes the framework refusal or is the same shape in miniature.

### The new evidence (post-dating the latest 2026-07-01 refusal)

The **cross-pass convergence gate** shipped 2026-08-13 (commits `fd7d531` →
`b87b949`/`3684838`): `skills/review-pr/scripts/write-review-state.sh`
deterministically computes a 4-state verdict from objective state —
`converged` / `progressing` / `stalled` / `regressed` — plus `force_human`, from
tier counts + file-level finding-identity set-diff + round counts.

**What the gate actually catches (verified by fresh-context review):**
- **Cross-file regression** (`regressed` = `any(f not in prev for f in cur)` over
  file sets, line 188-189): a finding in a file NOT flagged last round →
  `regressed` → hard-stop. This is the dominant failure mode it was built for
  (PR #2632's >10-round loop).
- **All-tiers-flat stalls** (`stalled` = `round ≥ 3 AND not clean AND all three
  counts ≥ prev`, lines 124-130): no tier improved → `stalled` → hard-stop.

**What the gate does NOT catch (the ADR's original Context claim was wrong
here):**
- **Same-file whack-a-mole** (`stalled`'s `>=`-AND logic fails when any single
  tier dips — `CRITICAL_COUNT >= PREV` is False when Crit drops, even if Imp
  rises in the same file → reads `progressing`). The original ADR Context claimed
  `stalled` catches whack-a-mole. It does not — for the same-file case. It
  catches it only when the rising finding lands in a NEW file (then `regressed`
  catches it, not `stalled`).
- **Same-file tier reclassification** (Crit→Imp, same file → not `regressed` +
  Crit count dropped → `stalled` False → `progressing`).
- **Rounds 1-2** (`stalled` requires `round ≥ 3`).
- **Minor churn** (`finding_files` is Crit+Imp by construction, lines 16-18
  header / 176-177, 203 construction; Minor is structurally invisible to
  `regressed`; `stalled` sees Minor only on flat-or-up — a Minor dip breaks it).
- **State-file-write crash** (the fail-closed fallback at lines 205-209 guards
  only the convergence-computation python3 at line 171, NOT the final write at
  lines 242-275; if python3 is missing/broken at the final write, no state file
  lands and the auto-loop reads stale/absent state).

The 12-round incident (PR #2768, session `6e7c3bed`) ran a *hand-rolled* review
(not `review-pr`), merged via *raw `gh pr merge`* (no gate), and the convergence
gate did not exist yet. With `review-pr` + the convergence gate + the merge gate
(Slice 1, CI gated), the failure surface is different: the loop deterministically
auto-stops on cross-file `regressed` + all-tiers-flat `stalled`, and the merge is
computationally gated. The incident does not directly repeat under this design.

## Decision

Automate the **per-round "go" button** of the review→fix loop, bounded by the
deterministic convergence gate, with the operator at the stop points:

**Auto-continue** the next round (fix → re-run `review-pr`) when **all** hold:
- `convergence_state == "progressing"` (not converged/stalled/regressed)
- `force_human == false`
- `round < ceiling` (`REVIEW_PR_ROUND_CEILING`, default 5 — the existing knob,
  not new machinery)

**Hard-stop + escalate to the operator** when **any** holds:
- `convergence_state` ∈ {`stalled`, `regressed`}
- `force_human == true`
- `round >= ceiling` — the operator's "after X loops, user decides" gate

At a hard-stop the operator decides: continue (another round), accept-as-is,
wontfix-remainder, or escalate — the same human decision `review-pr`'s Phase 7
footer already names.

### The continue decision is a shell script, not prose

The continue/hard-stop decision moves into a **deterministic shell script**
(e.g. `skills/review-pr/scripts/should-continue-loop.sh`) that reads the state
file and returns `continue` / `stop` — NOT prose in SKILL.md. This:
- Makes the decision **computational** (the model calls the script, which is
  deterministic) — the maker≠checker case at the loop level.
- Makes the **audit guard mechanically enforceable** (grep the script's
  condition, mirroring check 57's bidirectional shape — the gate IS the script).
- **Closes the sync-seam** (the decision and the assertion are in the same
  executable, not split across SKILL.md prose + write-review-state.sh + audit
  check with no machine-check of consistency).

**Implementation requirements (to actually close, not create, the sync-seam):**
- **Replace, don't supplement, the SKILL.md prose.** Phase 7 step 2
  (`SKILL.md:314-344`) currently restates the full decision tree in prose. The
  script must *replace* that prose with a call (`bash should-continue-loop.sh;
  case $? in ...`) — not sit alongside it. Leaving the prose = 3 places
  (script + prose + audit) with no machine-check between script and prose = a
  new sync-seam. A check 59 can assert the script is *invoked* (positive grep)
  but cannot assert the prose is *gone* (a negative grep false-positives on the
  legitimate footer-rendering prose that references the same fields).
- **Drop the redundant `round < ceiling` clause.** Under
  `convergence_state == "progressing"`, `force_human == false` already implies
  `round < ceiling` (the writer sets `force_human = (round >= ceiling)` on the
  progressing path). Keeping the clause makes two scripts read
  `REVIEW_PR_ROUND_CEILING` independently = a new sync-seam. The continue
  condition is `convergence_state == "progressing" AND force_human == false` —
  two clauses, not three.
- **Specify the `last_sha` staleness contract.** Mode-12's fail-closed-on-stale
  only fires if the *detector* fires; a misfiring detector fails OPEN (the loop
  continues on stale `progressing`). The robust contract: the caller passes the
  expected HEAD SHA; `should-continue-loop.sh` fails closed if
  `state.last_sha != expected` OR the file is missing. mtime/round heuristics
  fail open — do not use them.
- **Fail-closed on a missing/non-boolean `force_human` field.** The "two
  clauses, not three" condition (`convergence_state == "progressing" AND
  force_human == false`) is only safe for state files the current
  `write-review-state.sh` writes — which always set `force_human`. An older
  state file (pre-convergence-gate) lacking the field, or a corrupted/hand-edited
  one with a non-boolean, must NOT be read as `force_human == false` (that would
  let the loop continue past the ceiling). `should-continue-loop.sh` must fail
  closed — treat as `force_human == true` → hard-stop — if `force_human` is
  missing or non-boolean, mirroring `convergence-merge-gate.sh`'s handling of a
  missing `clean` field (lines 132-138). Same shape for `convergence_state`
  itself.

### What this does NOT change (the retained invariants)

- **The merge stays a computational gate.** Slice 1's `convergence-merge-gate`
  (clean AND CI-green) and `ship-merge`'s scored gate are untouched. Auto-loop
  never authorizes a merge; the model never blesses a ship. No bad-ship path
  exists (verified by the bypass reviewer — both merge layers hold).
- **Per-finding verification stays fresh-context.** `review-pr` Phase 5 step 3.5
  dispatches a fresh general-purpose agent to refute each Critical/Important
  finding; the blind-spot hunter is a separate pinned-opus agent. The maker≠checker
  separation at the finding level is unchanged. BUT: the verifier is per-*finding*
  (refute flagged findings), NOT per-*fix* (did the fix introduce a new bug) —
  see residual risk #2.
- **The continue decision is deterministic**, from `write-review-state.sh`'s
  computed verdict — never the model's self-reported confidence.
- **No self-launch.** This is auto-continue *within* an operator-started
  session, not a launchd/cron/`claude -p` self-start. The operator starts round
  1; the loop auto-continues to the stop point. No scheduler, no detached
  process, no survival across session exit.

## Residual risk (named, not zero — verified by fresh-context review)

1. **Compounding entanglement (not just burn).** Same-file churn: the ADR's
   original framing was "the ceiling bounds the burn." The real harm is a file
   mutated 2-5× by a model re-introducing a bug in the same file — harder to
   recover than the original bug. The merge gate prevents bad-ship (non-clean
   blocks merge), but the compounding+burn is real. **Mitigation:** the ceiling
   (5) bounds the rounds; the operator is at the ceiling. **Revisit trigger:**
   if a same-file-churn burn incident occurs (the loop churns ≥3 rounds reading
   `progressing` on a same-file regression), close this ADR (revert to
   human-started) + upgrade `regressed` to line-level identity (the AST-layer
   upgrade, currently out of scope — "Agents Need an AST Layer").

2. **The gate scores model-supplied counts (input-layer circularity).** The
   convergence gate is a faithful verifier, but its inputs — tier counts and
   `finding_files` — are the model's own aggregation. The *decision* to
   continue is separated (the script decides, not the model), but the *input*
   is not: the model tiers findings, the gate counts them. The crux (§56) names
   this — "scoring without separation = the maker grading its own homework with
   a rubric it wrote." Two paths exploit it:
   - **Within-round mis-tiering (active):** a real defect mis-tiered as Minor
     with no other Crit/Imp present → `CRITICAL_COUNT=0 AND IMPORTANT_COUNT=0`
     → step 3.5 has nothing to refute (it only *demotes* flagged findings, never
     *promotes*, and has nothing to verify at 0 Crit/Imp; `SKILL.md:139`) → on a
     trivial diff the blind-spot hunter skips (`SKILL.md:163`) → `clean=true` →
     loop stops → human merges on a buggy diff. (If a real Important *does*
     survive, step 3.5 runs on it, the hunter-skip path is not taken, and the
     loop continues fixing — but `clean=true` only requires `CRITICAL_COUNT==0`,
     so a *separate* Minor-mis-tiered defect still slips through the clean pass.)
     The model (deliberately or via shared blind spot) fed the count the gate
     scored.
   - **Reviewer miss + hunter-runs-but-misses (passive):** on a multi-file PR
     the hunter *does* trigger, but it is an LLM — a shared blind spot can
     survive a reframe. Reviewers miss + hunter misses → same `clean=true` →
     merge. (The earlier framing named only the hunter-*skips* case, not the
     hunter-*runs-but-misses* case.)
   Inherited from the human-started loop, but the auto-loop's reduced
   round-by-round human context (no per-round "go" click + skim) makes the
   clean verdict more rubber-stamp-prone. **Mitigation:** none in the auto-loop
   itself; the operator at the hard-stop must read the diff, not rubber-stamp
   the clean verdict. An implementation that wants to close this would require
   the blind-spot hunter to run on ALL diffs (not skip trivial ones) and/or
   add a fresh-context re-tier verifier. **Revisit trigger:** if a clean-pass
   incident occurs (latent bug → clean → merge on a buggy diff), close this ADR
   + require the hunter on all diffs.

3. **Token burn is bounded, not zero.** Up to `ceiling` unattended rounds of
   `review-pr` (each spawning ≤5 routed reviewers + a fresh verifier per
   Critical/Important finding + a blind-spot hunter) before the human gate. This
   is real cost; the operator's per-round click in the current design is what
   prevents it. **Mitigation:** the ceiling is the existing knob; an operator
   who wants it lower sets `REVIEW_PR_ROUND_CEILING=3` (or 2, to make round 1
   the only unattended one).

4. **The model is in the loop-level execution.** Even with the deterministic
   continue decision, the model is the one running each round (aggregating,
   tiering, selecting the next fix). This is the residual self-start the
   invariant named. The defense: the *decision* to continue is not the model's
   (it's the shell script's), and the *ship* is not the model's — only the
   per-round execution is. If that distinction proves load-bearing-wrong in
   practice, the revisit trigger fires.

5. **State-file-write crash.** The fail-closed fallback (lines 205-209) guards
   only the convergence-computation python3 (line 171). The final state-file
   write (lines 242-275) has no fallback; if python3 is missing/broken there, no
   state file lands and the auto-loop reads stale/absent state. **Mitigation:**
   the should-continue-loop script must fail-closed on a missing/stale state
   file (treat as `force_human=true` → hard-stop), not allow.

## What this is not the 5th refusal (rebuttal table)

| Refusal reason | This ADR |
|---|---|
| "classifying criticality at runtime needs an LLM" | ✗ the continue decision reads the deterministic `convergence_state` from the shell script |
| "confidence-based gating = model self-report" | ✗ the signal is the convergence gate's computed verdict, not model confidence |
| "auto retry/re-plan = the ladder" | ⚠ partial — this IS auto retry/re-plan, but bounded by a deterministic stop + a human ceiling gate. The ladder's structural definition (per ADR 0006 itself) was the **ratchet** — flag-gated escalation across notches — which this ADR does not re-arm (no flag, no notches, no self-launch, no auto-push). L3's substance was auto-continue within a human-started session, coupled to the flag; 0006 did not merely retire the flag, it **stripped `--auto` and restored the per-iteration human gate**. Refusal #3 refused the *shape* ("auto retry/re-plan IS the ladder") unconditionally — it did not condition on a stop, a flag, or bounds — and refused a *bundle* ("mandatory-verify-everything **plus** auto-retry"); this ADR has only the second half. The convergence gate (shipped 2026-08-13, post-dating the refusal) is a deterministic non-convergence signal L3 lacked — new evidence about the *stop*, not the *shape*. **The operator must engage explicitly whether bounded auto-continue (no ratchet) is L3's retired shape re-armed or a separable loop behavior.** |
| "no model self-start" | ⚠ the model auto-presses "go" per round. The crux page (§88: "never let a model raise its own autonomy ceiling — that is the generator appointing its own verifier") frames "no model self-start" as an *expression* of maker≠checker. **The source ADR 0006 scopes it to self-launch** ("the launchd self-start is gone... no OS-scheduler self-start"), so a per-round continue within an operator-started session is not self-start in 0006's sense — the *compressed* doctrine (CLAUDE.md/decay-cadence) states it flatly, but the source does not. §88's literal concern (the model appointing its own verifier) is not violated: the continue decision is a shell script, not the model, and the ceiling is raised by the operator via this ADR, not by the model. §56 (input-layer circularity — the gate scores the model's own counts) is the real residual, named as risk #2. **The operator's residual question is the L3-shape one above, not a blanket "self-start" ban.** |

## What this ADR does NOT authorize

- Auto-merge. The merge gate stays computational + human-only (`ship-merge`).
- Self-launch (launchd/cron/`claude -p`). Still retired.
- Model-confidence gating. The continue decision stays deterministic.
- Auto-loop on any loop other than review→fix (not `recursive-improve`, not
  `iterate-skill` — those stay human-started per iteration; their stop
  conditions are different and this ADR's evidence doesn't extend to them).
- Bypassing the ceiling. The ceiling is a hard human gate, not advisory.

## Revisit trigger

If any of these incidents occur under this design, close this ADR (revert to
human-started per round):
1. A same-file-churn burn incident (the loop churns ≥3 rounds reading
   `progressing` on a same-file regression).
2. A trivial-diff clean-pass incident (latent bug → clean → merge on a buggy
   diff).
3. A state-file-write-crash incident (the auto-loop reads stale/absent state
   and continues on a non-converged review).

This ADR's safety rests on the convergence gate catching non-convergence; if it
doesn't, the human-per-round click is the proven backstop.

**All three are post-incident, not proactive.** No mechanism surfaces them in
real time — they rely on a post-hoc human noticing. The ceiling hard-stop
fires at round 5, but between round 3 (where `stalled` first could catch flat
churn) and the ceiling, a same-file regression churns silently reading
`progressing`, and the operator at the ceiling cannot distinguish "genuinely
slow convergence" from "the gate missed a same-file whack-a-mole." For an
auto-loop, the absence of a proactive churn detector is a real gap: the ceiling
catches the burn but not the cause. A close condition that fires post-merge
(trigger #2) is, by definition, a revert, not a prevention.