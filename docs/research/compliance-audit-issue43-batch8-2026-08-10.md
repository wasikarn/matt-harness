# Compliance audit — issue #43 batch 8 + ship-merge.md follow-up

Date: 2026-08-10. Audits commits `0e6e8ef` (v0.68.256, batch 8 — 6 files) and `424cc62`
(v0.68.257 — the `ship-merge.md` follow-up), per `kbg:compliance-audit`. Full checklist and
verifier partition: `~/.claude/plans/gleaming-dreaming-ritchie.md` (the approved audit
plan — no formal `EnterPlanMode` artifact exists for the *original* implementation work being
audited, only for this audit itself; see D1 below).

## Result: 26/26 CONFORMS, 0 open

One requirement was initially DEVIATED (found by V4, not pre-declared) — fixed in this same pass
and independently re-verified CONFORMS before this report was written.

| Requirement group | Verifier | Count | Verdict |
|---|---|---|---|
| Issue #43's own re-graded files (R1, R2, R5, R6, R7, R8, R9, R10, R21) | V1 | 9 | CONFORMS |
| Freshly-graded files' soundness (R3, R4) | V2 | 2 | CONFORMS |
| Process/discipline conformance (R11, R13-R20, R22) | V3 | 10 | CONFORMS |
| `ship-merge.md` adversarial gate-integrity (R23-R26) | V4 | 4 | 3 CONFORMS, 1 initially DEVIATED → fixed → CONFORMS |

**Total: 26/26 CONFORMS. 0 open.**

## Pre-declared deviations (Phase 2) vs. what verifiers independently found

| # | Deviation | Independently confirmed? |
|---|---|---|
| D1 | No formal plan-mode artifact for the *original* work | Not directly checkable by a verifier (a process fact, not a diff fact) — disclosed as-is, consistent with V3's R17/R18 note that the `AskUserQuestion` interactions themselves are outside what repo state alone can verify |
| D2 | `ship-merge.md` fix is scope issue #43 never listed, authorized via a stated assumption rather than a formal `AskUserQuestion` before starting | V3's R22 independently confirmed the shipped report never inflates issue #43's own file count to include it — the process deviation is accurately disclosed, not silently absorbed |
| D3 | `score-decision/SKILL.md` shows no diff — re-grade found the gap already closed | V1's R6 independently confirmed: `git show 0e6e8ef -- skills/score-decision/SKILL.md` is empty, and the file's pre-existing `Re-score when` field genuinely satisfies the gap. Matches D3 exactly. |
| D4 | The `ship-merge.md` fix took 3 internal review rounds, framed as stronger-than-baseline adherence | **Partially reframed by this audit's own finding** — see below |
| D5 | Batch-8 report's Limitations section amended after initial commit once the follow-up was authorized | V2 and V3 both independently confirmed the amended note is accurate against current file content |

**D4 reframed, not falsified.** 3 rounds of `code-reviewer` dispatch during implementation caught 2 real bugs before either was ever committed — genuinely stronger than this backlog's baseline (a single review pass). But V4's own adversarial trace found a **4th** bug that survived all 3 rounds and reached the committed `424cc62`: a wording hedge in step 4 ("`--admin` may still be needed...") that implied a conditional bypass path step 5/6's actual mechanics never offered. This is exactly the outcome the audit plan's own mandate language anticipated ("three bugs already caught... assume a 4th is open until traced") — it isn't a failure of the 3-round process, it's the reason a maker≠checker audit exists at all: the same session's own review, however many rounds, is still the maker grading itself. An independent, differently-angled trace (an 8-cell truth table read against three separate pieces of the same file — step 4's prose, step 5's question stem, step 6's actual command block — rather than re-reading step 5's logic in isolation) is what surfaced it.

## The one finding, fixed in this pass

**[DEVIATED → fixed]** `commands/ship-merge.md` Phase 2 step 4's rebase/CI-N/A carve-out (added in round 3 of the `424cc62` fix) said `--admin` "may still be needed" in that case — implying a conditional path. But step 5's question stem asserts unconditionally "Branch protection active — this merge uses --admin to bypass it," and step 6's command block has exactly two forms (no protection → plain, protection active → `--admin`), no third conditional form. The hedge overstated what the mechanics actually do.

Fix: reworded step 4's closing sentence to state `--admin` is used unconditionally whenever protection is active (matching step 6's real binary logic), keeping only the informational distinction about *why* (an unvalidated-CI reason vs. some other protection rule, e.g. required reviews). Also tightened two "step N" references that ambiguously mixed this phase's own step numbers with Phase 1's (line 72's "step 2"/"step 3", line 73's "step 2", line 74's "step 2") into explicit "this phase's step N" / "Phase 1 step N" — a secondary finding V4 flagged as a live ambiguity risk, and two more instances of the identical pattern caught in a self-directed follow-up sweep of the same block, closed in the same edit for consistency.

Independently re-verified by a second fresh-context agent against the full 8-combination truth table (branch protection × rebase result × CI signal): confirmed all four protection-active sub-cases now consistently use `--admin` across step 4, step 5's stem, and step 6's commands, with no remaining contradiction.

## Verification

- `run-gauntlet.sh`: green, fresh run (V3, and re-confirmed after the remediation fix).
- `git log origin/develop` vs. local `git log`: matched for the audited range before this remediation — nothing pushed-then-rewritten.
- Char-deltas independently recomputed by V3 for all 7 files across both commits (the 6 batch-8 files + `ship-merge.md`'s own 424cc62 delta) — all match the batch-8 report's table exactly, none exceed 20%.
- File-touch sanity check (V3, R20): no unrelated files in either commit, no `git add -A` signature.

## Suggested next step

All 26 requirements conform, nothing open. The remediation fix (`--admin`-unconditional wording + 4 reference-qualifier fixes) is ready to commit and push — no further audit round needed for it, since it's the same narrow class of fix already independently re-verified above.
