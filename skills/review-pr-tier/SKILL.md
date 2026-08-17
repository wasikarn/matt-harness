---
name: review-pr-tier
description: "Tier and scrutinize kbg:review-pr's findings (SCRUTINIZE-4, adversarial verify, blind-spot re-hunt). Use when kbg:review-pr hands off after Phase 4. Don't use for self-invoked or standalone review."
metadata:
  origin: kbg
---

# Comprehensive PR Review — Tier Findings (Phase 5)

Second link in the `kbg:review-pr` → `kbg:review-pr-tier` → `kbg:review-pr-finish` chain — a
3-way split of what was one oversized `review-pr/SKILL.md` (2026-08-17), so each link stays
under harness-audit's 20,000-char threshold and gets its own protected slot on auto-compaction
re-attachment (`code.claude.com/docs/en/skills` § Skill content lifecycle). Never invoked
directly by a user or standalone — `kbg:review-pr`'s Phase 4 calls `Skill(kbg:review-pr-tier)`
as a mandatory next step once agents are dispatched.

**First action — read the checkpoint, before anything else.** `kbg:review-pr`'s Phase 4 writes
a checkpoint before handing off; runtime state (the pinned SHAs, dispatched agent findings)
lives in conversation/tool-output history otherwise, which auto-compaction can clear *before*
skill re-attachment even applies. A surviving skill body doesn't recover destroyed variables —
that's what the checkpoint is for.

```bash
CKPT_JSON=$(bash "${KBG_PLUGIN_ROOT}/skills/review-pr/scripts/read-review-checkpoint.sh" 4 "$HEAD_SHA" "${WT:-}")
```

Use the `$HEAD_SHA` you already hold from the hand-off (this script does not call `git` itself —
mirrors `should-continue-loop.sh`'s own pure string-compare convention; a live git-derive here
would reject every legitimate PR-by-number hand-off, since Phase 2 works from an isolated
worktree). **On any non-zero exit: stop, name the exact `reason=` token from the script's
output, and tell the human plainly** — do not guess or proceed on partial/assumed values, and
do not attempt to reconstruct the missing state from conversational memory. On success, parse
`base_sha`, `agent_findings`, and `dispatch_failures` out of `$CKPT_JSON`.

**Defensive re-derivation** (cheaply re-derivable — never checkpointed): confirm `$WT` via
`git worktree list` if this is a PR-by-number review; re-derive the changed-file list via
`git diff --name-only "$BASE_SHA".."$HEAD_SHA"` if needed.

---

## Phase 5: Aggregate + Tier Findings (Scrutinize Gate)

**Goal**: Consolidate findings, classify into severity tiers — **without** blending across agents. Apply outsider-perspective scrutiny before presenting.

**Actions**:
1. Collect all per-agent findings (from the checkpoint's `agent_findings`). **Do NOT blend findings across agents** (surface conflicts, don't average — each agent's report stands independently. Overlap between agents on the same file:line = signal, not noise. Preserve attribution: "code-reviewer + security-reviewer both flagged this" tells the user something dedupe would erase.)
2. **Apply SCRUTINIZE-4 to every finding** (named gate — the 4 questions are *falsifiable*, not vibes). A finding that fails any check goes to `.scratch/review-pr-<timestamp>/rejected.md` with the failing question + reason; the user sees the rejection tally, not the dropped finding:

   | # | Question | Falsifiable check (pass = ) | Reject if |
   |---|----------|-----------------------------|-----------|
   | 1 | **Challenge intent** — is there a simpler way? | You can name the simpler alternative in one sentence, OR you can name why the existing approach is the right one | No alternative named AND no justification for the current shape |
   | 2 | **Trace the call graph** — does the change interact with unmodified callers in surprising ways? | You followed the call path; the result is "safe" or "unsafe" with `file:line` evidence | You only read the diff, not the callers |
   | 3 | **Verify real execution branches** — does the fix break the error path / edge case? | You named at least one branch (success + 1 error/edge) and traced it, AND for each branch that could host the defect noted whether a test reaches it — an untested defeating transition means a regression here escapes the suite, raising the finding's effective risk (flag `[untested-transition]` in the finding). This is the tathep `compliance-audit-round-2` gap: a CRITICAL hid through 9 review rounds because no test exercised the defeating state-transition, so every pass read "code path covered" as "safe" while the transition that actually defeated the fix was never reached | You traced the happy path only, OR you named a branch but didn't note its test-reach |
   | 4 | **Evidence requirement** — what supports the claim? | Finding has `file:line` (or commit SHA) + the *minimal* command/output that confirms it | Claim is plausible but unverified (matches "26-50" confidence from `code-reviewer` agent frontmatter — drop) |

   **Why named and tabular:** the prose version of this gate was skipped in real runs because it was exhausting. The named checks turn "did I scrutinize?" from a vibe into a yes/no per finding. The reject-and-log path means dropping a finding is *auditable* — the user can see what got filtered and why (vs the agent's confidence-threshold which is invisible).

   **Audit trail — `rejected.md`.** The dropped findings are not issues (don't use `.scratch/<feature>/issue.md`); they are an ephemeral audit log of a single review session. Write them to `.scratch/review-pr-<UTC-timestamp>/rejected.md` (e.g. `.scratch/review-pr-2026-06-08T15-30Z/rejected.md`) with one line per dropped finding: `- [Q3] hooks/gates/irrecoverable.sh:50 — "happy path only, didn't trace the sudo-wrapped branch"`. The dir is gitignored-by-convention under the issue-tracker's "scratch is local" rule; the user sees only a tally `Rejected: 4 (Q1: 0, Q2: 1, Q3: 2, Q4: 1)`, not the dropped body. **`rejected.md` is structured data, not narration — don't add a free-text summary sentence** (e.g. "all N candidate findings passed all four checks") on top of the per-line list and tally. Confirmed failure mode: that kind of prose count drifts from the actual tally the moment a finding surfaces mid-session (step 3.5's new mid-verification bullet above can add one), producing a file that contradicts itself within the same few lines. The structured tally is the only summary this file needs — if you state a total, derive it by counting the lines, don't restate a number from memory.

3. **Consolidate into severity tiers.** For each finding, assign a tier by asking *"if this ships as-is, what's the worst that could happen?"* — production breaks / a 2am page / silent data corruption / users see errors → **Critical**; a real but contained issue → **Important**; only "the code is slightly less clean" → **Minor**:
   - **Critical** — must fix before merge (security, data integrity, broken functionality)
   - **Important** — should fix before merge (real issues that don't block but shouldn't ship)
   - **Minor** — nice to have (style, optional refinements)

   **Requirement-coverage findings tier the same way, no special-casing** — they arrive as ordinary `code-reviewer` findings (Phase 4 step 3.5's lens dispatch), so they flow through SCRUTINIZE-4 and step 3.5's adversarial verifier below exactly like any other finding. This is load-bearing, not incidental: a coverage finding claims "not in the diff," and the "already implemented elsewhere" false-positive that risk is exactly what the fresh-agent refutation below exists to catch — don't route these around it.
3.5. **Independent adversarial verification — Critical/Important findings only.** SCRUTINIZE-4 (step 2) is self-graded: the same orchestrator context that ran the checklist decides whether its own checklist passed. That's the maker grading its own work — the exact pattern CLAUDE.md's verifier-separation principle rejects everywhere else in this harness. This step is the actual independent check: for every unique Critical/Important finding, dispatch a **fresh** agent (the general-purpose type, not the specialist that raised the finding — a fresh generalist lens is what makes it independent, not a repeat of the same specialist's framing) with the finding's description + file:line + evidence, instructed to *try to refute it* by reading the real code at that location. The verifier returns a structured verdict: `isReal` (bool), `confidence` (0.0–1.0), `reasoning` (one paragraph).

   **Fail-closed disposition** (mirrors ECC's `orch-review` Workflow verify stage):
   - `isReal: true`, or `isReal: false` with `confidence < 0.8` → **stays at its tier.** An unconfident refutation doesn't override the original reviewer.
   - `isReal: false` with `confidence >= 0.8` → **demote one tier** (Critical → Important, Important → Minor) and tag `[verifier-refuted, confidence: 0.NN]` in the presented finding (Phase 6, in `kbg:review-pr-finish`) — visible to the user, not silently dropped.
   - Verifier errors, times out, or returns an unparseable verdict → **stays at its tier.** Same principle as Phase 4 step 4: a missing response is not evidence the finding is wrong.
   - When there are zero Critical/Important findings, this step has nothing to verify — hand off to **step 3.6**, which runs the symmetric guard for that case (a shared blind spot produces *no* finding, and step 3.5 only checks findings that already exist).
   - **A verifier surfaces an entirely new finding while checking a different one** (not confirming/refuting the finding it was dispatched against, but something else noticed along the way) → route that new finding back through step 2's SCRUTINIZE-4 gate before it enters the tier table, and update `rejected.md`/`ledger.md`'s counts to include it. Never let a finding skip the same gate every other finding cleared just because of when it surfaced — confirmed gap: a finding that emerged this way once matched Important-tier evidence but never appeared in `rejected.md`'s SCRUTINIZE-4 tally, so the presented "N findings passed all four checks" summary silently overcounted.

   This roughly doubles dispatches on a review with several such findings (see
   `../review-pr/reference.md` § Integration Notes — full detail, "Token budget" bullet). It closes the *independence*
   gap, not the *empirical-grounding* gap (a correlated hallucination across same-distribution
   reviewers can still survive) — that second gap is `kbg:review-pr-finish`'s Phase 6
   proof-verification check (own-branch flow) and `/ship-merge` Phase 1 step 6's distrust of
   same-session self-tiering on sensitive diffs.
3.6. **Zero-findings adversarial re-hunt — the blind-spot guard.** Step 3.5 only checks findings
   that already exist — it does nothing when reviewers return zero Critical/Important findings,
   exactly the shared-blind-spot case (a false *negative* no refutation can catch). When **zero
   Critical/Important findings remain after step 3.5's dispositions** — either none were raised, or
   every one was refuted down to Minor (the trigger is the *final* state, not what step 3 first
   produced) — AND the diff is **non-trivial** (≥2 files changed or ≥1 test file touched — same
   threshold as `kbg:review-pr-finish`'s Phase 6 proof check), dispatch **`agents/blind-spot-hunter.md`**
   directly, framed with the pinned range (`$BASE_SHA..$HEAD_SHA`) as its target diff: instruct it
   to *assume a defect exists and go find it* — re-reviewing with the same lens just reproduces the
   zero; the reframe from "check this" to "there is a bug here — locate it" is what gives a shared
   blind spot a chance to surface. `blind-spot-hunter` is this step's purpose-built agent — pinned
   `opus`, trace-to-earned-severity, a "Cleared decoys" list, fail-closed refutation already built
   in — not a generic agent re-framed by this step's own prompt. The hunter returns structured
   findings (possibly none). (Standalone dispatchable form: `../review-pr/reference.md`.)
   - **Any Critical/Important finding it raises is verified before it counts.** A hunter told "assume a bug exists" is primed to manufacture a weak one — the exact false positive step 3.5 exists to kill — so apply step 3.5's fail-closed refutation (a *fresh* refuter, same disposition) to each hunter finding once, then tier it. The re-hunt itself runs **once**: a hunter finding never triggers another step 3.6, so the pass always terminates.
   - **Returns nothing** → the zero-findings clean pass stands, now backed by an independent adversarial pass. Record that the re-hunt ran (`kbg:review-pr-finish`'s Phase 6 surfaces it).
   - **Skip** on a trivial diff (a single non-test file) — Rule 2, not worth the *hunter* dispatch — and whenever any Critical/Important finding *survives* step 3.5 (there's already a real finding to act on; step 3.5 owns that path). **This economy is scoped to step 3.6's own dispatch only** — it is not a general license to skip or substitute agents anywhere else in the review, including Phase 3's reviewer fan-out (in `kbg:review-pr`; Phase 3's own trivial-diff rule governs what may be skipped there, and it is narrower than this one).
   - Hunter errors, times out, or returns unparseable output → treat as **re-hunt-not-run**, not as a clean result (Phase 4 step 4's principle: a missing response is not evidence the code is clean). Surface it so the clean verdict isn't overstated.
4. **Zero findings is a valid clean pass — a missing report is not, and on a non-trivial diff it must clear step 3.6 first.** `agents/code-reviewer.md` explicitly sanctions a bare zero-findings APPROVE ("do not withhold approval to appear rigorous") — don't demand narration a clean pass doesn't need. What actually distinguishes "checked and clean" from "didn't check" is that Phase 4 hands every agent the exact pinned range (`$BASE_SHA..$HEAD_SHA`): a zero-findings return against a known, scoped diff *is* the clean signal — backed, on a non-trivial diff, by step 3.6's adversarial re-hunt so the clean verdict isn't just the reviewers' shared blind spot restated. The failure mode this guards against is an agent that never returns at all — that's `dispatch_failures` from Phase 4 step 4 (in the checkpoint), not a clean tier. Surface to the user which agents returned clean, which returned findings, and (if any) which are in `dispatch_failures` — the latter blocks a clean overall verdict regardless of what the other agents found.
5. **Apply ledger-driven tightening (if eligible).** Read `../review-pr/policy.md` § Threshold and the rolling 10-session aggregation. If any Q is eligible (≥50% rejection rate, ≥5 sessions), apply the *tightened* check from the policy table for that Q *this session only*. Surface a note: `Q3 tightened for this session (67% rejection over 10 sessions — was 45%)`. The user can override by saying "skip the policy" — the default SCRUTINIZE-4 check is then used and the ledger records `policy_skipped: true`.
6. **Write the ledger entry.** Sibling of `rejected.md`, in the same `.scratch/review-pr-<UTC-timestamp>/` dir. See `../review-pr/ledger.md` for the schema. Per-Q counters (Rejected / Survived / %), agents dispatched, scope identifier, and `policy_skipped: true` if applicable. **Prune first** — count existing `ledger.md` files, FIFO-remove oldest until count ≤ 199, then write the new entry. This keeps the rolling window bounded per `ledger.md` § Retention.
7. Surface a tier-grouped finding table to the orchestrator (you), not yet to user — `kbg:review-pr-finish`'s Phase 6 handles user presentation.

**Named models** (cc-thinking-skills): the SCRUTINIZE-4 falsifiable checks + multi-agent overlap (don't blend, surface conflicts) are *red-team* (argue against the finding) + *steel-manning* (synthesize the strongest version of the reviewer's concern before deciding to reject); tier assignment by "worst that could happen" is *pre-mortem* (catastrophic-failure branch first, detection, rollback). Catalog + honesty caveat: read via Bash with `cat "${KBG_PLUGIN_ROOT}/docs/reference/reasoning-models.md"`.

---

**Hand off to `kbg:review-pr-finish`.** Phase 5 is done — write the checkpoint, then call
`Skill(kbg:review-pr-finish)` next:

```bash
PAYLOAD="${TMPDIR:-/tmp}/review-pr-p5-$$.json"
# build {"tier_list": [...]} into $PAYLOAD — the tier-grouped findings from step 7 above
bash "${KBG_PLUGIN_ROOT}/skills/review-pr/scripts/write-review-checkpoint.sh" 5 "$HEAD_SHA" "${WT:-}" "$PAYLOAD"
```

`$PAYLOAD` also carries the `rejected.md`/ledger state from step 6. This is a mandatory next step, not a
suggestion — the review is not complete until `kbg:review-pr-finish`'s Phase 6 and 7 have run.

**Reference tables** (aspect routing, agent descriptions, tips, workflow examples):
`../review-pr/reference.md`.

## Notes

- Agents run autonomously and return detailed reports
- Each agent focuses on its specialty for deep analysis
- Results are actionable with specific file:line references
- Agents use models per their frontmatter (`model:` field)
- Routed agents listed via `kbg:inventory` (your skill that lists everything available) or `claude agents` CLI — **not** `/agents` (that's a UI command for managing definitions, not a listing)

---

## Integration Notes (Project-Specific)

- **Scope**: reviews code, not CI status — this skill never checks or gates on `gh pr checks`
  (that belongs to `/ship-merge`'s own required-checks gate). Auth/secrets-touching diffs get
  `security-reviewer`'s fast in-review flag (`kbg:review-pr`'s Phase 3); a deeper standalone
  threat-model audit is `kbg:security-auditor` — a separate skill, run it directly when the diff
  warrants one.
- Severity tiers and SCRUTINIZE-4 are defined in full in Phase 5 above — this section doesn't
  repeat them. Token-budget estimate, hooks active during a session, the GH CLI submission
  mechanics (covered in `kbg:review-pr-finish`'s Phase 7 step 3), the full routing-reference
  table, and the rejection-rate ledger spec: `../review-pr/reference.md`.

**Done when**: every collected finding has cleared (or been rejected by) SCRUTINIZE-4, every
Critical/Important finding has an adversarial disposition (step 3.5) or the diff cleared the
zero-findings re-hunt (step 3.6), the ledger entry is written, and the checkpoint + hand-off to
`kbg:review-pr-finish` are complete.
