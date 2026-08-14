# ADR 0007 — Bounded review→fix auto-loop (the per-round "go" button)

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

**The one thing the operator must resolve before acceptance:** the doctrine's
"no model self-start" is stated flatly, without scoping it to irreversible
boundaries. The ADR reads it as an expression of maker≠checker (scoped to
one-way doors, so a reversible per-round continue is substitutable by a
deterministic gate). The refusal's literal words read it as blanket. **That
ambiguity is the operator's to resolve — not the ADR's to settle unilaterally.**
The operator must engage the steelman's strongest point (refusal #3 refused the
*shape* "auto retry/re-plan IS the ladder," not the stop; the expression-vs-
principle distinction is self-graded) before moving this ADR from Proposed to
Accepted. Without that, the "Why this is not the 5th refusal" table is the maker
grading its own work — the exact circularity the crux exists to prevent.

## Context

### What ADR 0006 retired and why

ADR 0006 retired the L2–L5 autonomy ladder (L3 bounded autonomy, L4 self-launch,
L5 auto-push) and codified the operating model (`CLAUDE.md` §Architecture): *deny
the irrecoverable set computationally, advise on the rest; the operator is the
authority at every irreversible boundary; no model self-start.* The retiring
crux (`agent-loop-verifier-crux.md`): *the gate is a verifier, the model is the
maker, and the maker can never grade its own work — "two optimists agreeing."*

This design (let the model auto-continue the review→fix loop) was proposed
**4×** and refused **4×** (`docs/harness-decay-cadence.md` §"Refused extension";
memory `rgs-pushback-descope-2026-07-01`). The four refusal reasons:

1. Classifying decision criticality at runtime needs an LLM (unverified
   reasoning gating reasoning) or deterministic semantic understanding of free
   text (not buildable).
2. Confidence-based gating uses model self-report as the gate signal — same
   crux.
3. Mandatory-verify-everything + auto retry/re-plan/escalate is the L2–L5 ladder
   under a new name — retired, do not re-arm.
4. No model self-start.

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
- **Minor churn** (`finding_files` is Crit+Imp by construction, line 272-274;
  Minor is structurally invisible to `regressed`; `stalled` sees Minor only on
  up-ticks).
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

2. **The fresh verifier is per-finding, not per-fix.** `review-pr` Phase 5 step
   3.5 dispatches a fresh agent to *refute each Critical/Important finding* — it
   is never asked "is the fix correct?" or "did the fix introduce a new bug?"
   A wrong fix that resolves the flagged finding (count drops) and introduces an
   unflagged latent bug is invisible to step 3.5. The guard for fix-induced
   latent bugs is the next round's review + the blind-spot hunter (which
   **skips on a trivial diff**, `SKILL.md:163`). So a 1-file fix that introduces
   a latent bug: reviewers miss it → zero findings → hunter skips →
   `rehunt="skipped-trivial"` → `clean=true` → loop stops → human merges on a
   subtly buggy diff. Inherited from the human-started loop, but the auto-loop's
   reduced human round-by-round context (they didn't click "go" each round and
   skim each round's findings) makes the clean verdict more rubber-stamp-prone.
   **Mitigation:** none in the auto-loop; the operator at the hard-stop must
   read the diff, not rubber-stamp the clean verdict. **Revisit trigger:** if a
   trivial-diff clean-pass incident occurs (latent bug → clean → merge on a
   buggy diff), close this ADR + require the blind-spot hunter to run on ALL
   diffs (not skip trivial ones).

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
| "auto retry/re-plan = the ladder" | ⚠ partial — this IS auto retry/re-plan, but bounded by a deterministic stop + a human ceiling gate. Refusal #3 refused the *shape* ("auto retry/re-plan IS the ladder"), not the stop. The distinguishing fact (the convergence gate, shipped 2026-08-13, post-dating the latest refusal) is a deterministic non-convergence signal L3 lacked. **But:** refusal #3 did not condition on the stop — so "new evidence about stops" does not address a refusal that refused the shape unconditionally. **The operator must engage this point explicitly.** |
| "no model self-start" | ⚠ the model auto-presses "go" per round. The crux page frames "no model self-start" as an *expression* of maker≠checker (line 88: "never let a model raise its own autonomy ceiling — that is the generator appointing its own verifier"). The ADR's expression/principle distinction IS the crux's own framing. But: "no model self-start" is stated flatly in the doctrine. **The operator must resolve this ambiguity.** |

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