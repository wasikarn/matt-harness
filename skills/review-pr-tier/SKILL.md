---
name: review-pr-tier
description: "Tier and scrutinize kbg:review-pr's findings (SCRUTINIZE-4, adversarial verify, blind-spot re-hunt). Use when kbg:review-pr hands off after Phase 4. Don't use for self-invoked or standalone review."
metadata:
  origin: kbg
---

# Comprehensive PR Review — Tier Findings (Phase 5)

Second link in the `kbg:review-pr` → `kbg:review-pr-tier` → `kbg:review-pr-finish` chain — a
3-way split of one oversized `review-pr/SKILL.md` (2026-08-17) so each link stays under
harness-audit's 20,000-char threshold and gets its own protected slot on auto-compaction
re-attachment (`code.claude.com/docs/en/skills` § Skill content lifecycle). Never invoked
directly or standalone — `kbg:review-pr`'s Phase 4 calls `Skill(kbg:review-pr-tier)` as a
mandatory next step once agents are dispatched.

**First action — read the checkpoint, before anything else.** `kbg:review-pr`'s Phase 4 writes a
checkpoint before handing off — runtime state (pinned SHAs, dispatched agent findings) otherwise
lives in conversation/tool-output history, which auto-compaction can clear *before* skill
re-attachment even applies. A surviving skill body doesn't recover destroyed variables.

```bash
CKPT_JSON=$(bash "${KBG_PLUGIN_ROOT}/skills/review-pr/scripts/read-review-checkpoint.sh" 4 "$HEAD_SHA" "${WT:-}")
```

Use the `$HEAD_SHA` you already hold from the hand-off — this script doesn't call `git` itself
(rationale: `../review-pr/reference.md` § Phase 5 step 3.6 — standalone form). **On any non-zero
exit: stop, name the exact `reason=` token from the script's output, and tell the human plainly**
— do not guess or proceed on partial/assumed values, and do not attempt to reconstruct the
missing state from conversational memory. On success, parse `base_sha`, `agent_findings`, and
`dispatch_failures` out of `$CKPT_JSON`.

**Defensive re-derivation** (cheaply re-derivable, never checkpointed): confirm `$WT` via
`git worktree list` for a PR-by-number review; re-derive the changed-file list via
`git diff --name-only "$BASE_SHA".."$HEAD_SHA"` if needed.

---

## Phase 5: Aggregate + Tier Findings (Scrutinize Gate)

**Goal**: Consolidate findings, classify into severity tiers — **without** blending across agents. Apply outsider-perspective scrutiny before presenting.

**Actions**:
1. Collect all per-agent findings (from the checkpoint's `agent_findings`). **Do NOT blend findings across agents** — surface conflicts, don't average; each agent's report stands independently. Overlap on the same file:line = signal, not noise. Preserve attribution: "code-reviewer + security-reviewer both flagged this" tells the user something dedupe would erase.
2. **Apply SCRUTINIZE-4 to every finding** (4 falsifiable checks, not vibes). A finding that fails any check goes to `.scratch/review-pr-<timestamp>/rejected.md` with the failing question + reason; the user sees the rejection tally, not the dropped finding:

   | # | Question | Falsifiable check (pass = ) | Reject if |
   |---|----------|-----------------------------|-----------|
   | 1 | **Challenge intent** — is there a simpler way? | Name the simpler alternative in one sentence, OR name why the existing approach is right | No alternative named AND no justification given |
   | 2 | **Trace the call graph** — does the change interact with unmodified callers in surprising ways? | You followed the call path; the result is "safe" or "unsafe" with `file:line` evidence | You only read the diff, not the callers |
   | 3 | **Verify real execution branches** — does the fix break the error path / edge case? | You named at least one branch (success + 1 error/edge) and traced it, AND for each branch that could host the defect noted whether a test reaches it — an untested defeating transition raises the finding's effective risk (flag `[untested-transition]`; precedent: `../review-pr/reference.md` § Integration Notes — full detail, "SCRUTINIZE-4 rubric" bullet) | You traced the happy path only, OR you named a branch but didn't note its test-reach |
   | 4 | **Evidence requirement** — what supports the claim? | Finding has `file:line` (or commit SHA) + the *minimal* command/output that confirms it | Claim is plausible but unverified (matches "26-50" confidence from `code-reviewer` agent frontmatter — drop) |

   **Why named and tabular, and the audit trail:** `../review-pr/reference.md` § Integration Notes — full detail, "SCRUTINIZE-4 rubric" bullet.

   **`rejected.md` format.** Dropped findings are not issues (don't use `.scratch/<feature>/issue.md`) — they're an ephemeral audit log of a single review session. Write to `.scratch/review-pr-<UTC-timestamp>/rejected.md`, one line per dropped finding: `- [Q3] hooks/gates/irrecoverable.sh:50 — "happy path only, didn't trace the sudo-wrapped branch"`. Gitignored-by-convention (scratch is local); the user sees only a tally `Rejected: 4 (Q1: 0, Q2: 1, Q3: 2, Q4: 1)`, not the dropped body. **Structured data, not narration — no free-text summary sentence** on top of the per-line list and tally (a prose count drifts from the actual tally the moment a finding surfaces mid-session — confirmed failure mode). If you state a total, derive it by counting the lines.

3. **Consolidate into severity tiers.** For each finding, assign a tier by asking *"if this ships as-is, what's the worst that could happen?"* — production breaks / a 2am page / silent data corruption / users see errors → **Critical**; a real but contained issue → **Important**; only "the code is slightly less clean" → **Minor**:
   - **Critical** — must fix before merge (security, data integrity, broken functionality)
   - **Important** — should fix before merge (real issues that don't block but shouldn't ship)
   - **Minor** — nice to have (style, optional refinements)

   **Requirement-coverage findings tier the same way, no special-casing** — they arrive as ordinary `code-reviewer` findings (Phase 4 step 3.5's lens dispatch), flowing through SCRUTINIZE-4 and step 3.5's adversarial verifier below like any other finding. Load-bearing: a coverage finding claims "not in the diff," and the "already implemented elsewhere" false-positive risk is exactly what the fresh-agent refutation below exists to catch — don't route these around it.
3.5. **Independent adversarial verification — Critical/Important findings only.** SCRUTINIZE-4 (step 2) is self-graded — why independence matters here: `../review-pr/reference.md` § Phase 5 step 3.6 — standalone form. For every unique Critical/Important finding, dispatch a **fresh** agent (the general-purpose type, not the specialist that raised the finding — a fresh generalist lens is what makes it independent, not a repeat of the same specialist's framing) with the finding's description + file:line + evidence, instructed to *try to refute it* by reading the real code at that location. The verifier returns a structured verdict: `isReal` (bool), `confidence` (0.0–1.0), `reasoning` (one paragraph).

   **Fail-closed disposition** (mirrors ECC's `orch-review` Workflow verify stage):
   - `isReal: true`, or `isReal: false` with `confidence < 0.8` → **stays at its tier.** An unconfident refutation doesn't override the original reviewer.
   - `isReal: false` with `confidence >= 0.8` → **demote one tier** (Critical → Important, Important → Minor) and tag `[verifier-refuted, confidence: 0.NN]` in the presented finding (Phase 6, in `kbg:review-pr-finish`) — visible to the user, not silently dropped.
   - Verifier errors, times out, or returns an unparseable verdict → **stays at its tier.** Same principle as Phase 4 step 4: a missing response is not evidence the finding is wrong.
   - When there are zero Critical/Important findings, this step has nothing to verify — hand off to **step 3.6**, which runs the symmetric guard for that case (a shared blind spot produces *no* finding, and step 3.5 only checks findings that already exist).
   - **A verifier surfaces an entirely new finding while checking a different one** → route it back through step 2's SCRUTINIZE-4 gate before it enters the tier table, and update `rejected.md`/`ledger.md`'s counts to include it. Never let a finding skip the same gate every other finding cleared just because of when it surfaced (confirmed gap: one such finding matched Important-tier evidence but never appeared in the SCRUTINIZE-4 tally, silently overcounting the presented summary).

   (Token-budget impact + the independence-vs-empirical-grounding scope of this step: `../review-pr/reference.md` § Integration Notes — full detail / § Phase 5 step 3.6 — standalone form.)
3.6. **Zero-findings adversarial re-hunt — the blind-spot guard** (why it exists + the agent's own traits: `../review-pr/reference.md` § Phase 5 step 3.6 — standalone form). When **zero
   Critical/Important findings remain after step 3.5's dispositions** — either none were raised, or
   every one was refuted down to Minor (the trigger is the *final* state, not what step 3 first
   produced) — AND the diff is **non-trivial** (≥2 files changed or ≥1 test file touched — same
   threshold as `kbg:review-pr-finish`'s Phase 6 proof check), dispatch **`agents/blind-spot-hunter.md`**
   directly, framed with the pinned range (`$BASE_SHA..$HEAD_SHA`) as its target diff, instructed to
   *assume a defect exists and go find it*. Returns structured findings (possibly none).
   - **Any Critical/Important finding it raises is verified before it counts** — apply step 3.5's fail-closed refutation (a *fresh* refuter, same disposition) to each hunter finding once, then tier it. Runs **once**: a hunter finding never triggers another step 3.6.
   - **Returns nothing** → the zero-findings clean pass stands, now backed by an independent adversarial pass; record that the re-hunt ran (`kbg:review-pr-finish`'s Phase 6 surfaces it).
   - **Skip** on a trivial diff (a single non-test file — Rule 2) or whenever any Critical/Important finding *survives* step 3.5. **Scoped to step 3.6's own dispatch only** — not a license to skip/substitute agents elsewhere (Phase 3's fan-out in `kbg:review-pr` has its own, narrower trivial-diff rule).
   - Hunter errors, times out, or returns unparseable output → **re-hunt-not-run**, not a clean result (Phase 4 step 4's principle). Surface it so the clean verdict isn't overstated.
4. **Zero findings is a valid clean pass — a missing report is not, and on a non-trivial diff it must clear step 3.6 first** (what makes it "clean" vs. "didn't check": `../review-pr/reference.md` § Phase 5 step 3.6 — standalone form). The failure mode this guards against is an agent that never returns at all — that's `dispatch_failures` from Phase 4 step 4 (in the checkpoint), not a clean tier. Surface to the user which agents returned clean, which returned findings, and (if any) which are in `dispatch_failures` — the latter blocks a clean overall verdict regardless of what the other agents found.
5. **Apply ledger-driven tightening (if eligible).** Read `../review-pr/policy.md` § Threshold (rolling 10-session aggregation). If any Q is eligible (≥50% rejection rate, ≥5 sessions), apply the *tightened* check from the policy table for that Q *this session only*. Surface a note: `Q3 tightened for this session (67% rejection over 10 sessions — was 45%)`. The user can override ("skip the policy") — the default SCRUTINIZE-4 check is then used and the ledger records `policy_skipped: true`.
6. **Write the ledger entry** (sibling of `rejected.md`, same `.scratch/review-pr-<UTC-timestamp>/` dir; schema: `../review-pr/ledger.md` — per-Q counters, agents dispatched, scope identifier, `policy_skipped: true` if applicable). **Prune first** — FIFO-remove oldest `ledger.md` files until count ≤ 199 (bounds the rolling window per `ledger.md` § Retention), then write the new entry.
7. Surface a tier-grouped finding table to the orchestrator (you), not yet to user — `kbg:review-pr-finish`'s Phase 6 handles user presentation.

**Named models** (cc-thinking-skills): SCRUTINIZE-4 + multi-agent overlap (don't blend, surface conflicts) are *red-team* + *steel-manning*; tier assignment by "worst that could happen" is *pre-mortem*. Catalog + honesty caveat: `cat "${KBG_PLUGIN_ROOT}/docs/reference/reasoning-models.md"`.

---

**Hand off to `kbg:review-pr-finish`.** Phase 5 is done — write the checkpoint, then call
`Skill(kbg:review-pr-finish)` next:

```bash
PAYLOAD="${TMPDIR:-/tmp}/review-pr-p5-$$.json"
# build {"tier_list": [...]} into $PAYLOAD — the tier-grouped findings from step 7 above
bash "${KBG_PLUGIN_ROOT}/skills/review-pr/scripts/write-review-checkpoint.sh" 5 "$HEAD_SHA" "${WT:-}" "$PAYLOAD"
```

`$PAYLOAD` also carries the `rejected.md`/ledger state from step 6. Mandatory, not a suggestion —
the review isn't complete until `kbg:review-pr-finish`'s Phase 6 and 7 have run.

**Reference tables** (aspect routing, agent descriptions, tips, workflow examples):
`../review-pr/reference.md`. (Agent-dispatch mechanics already covered in `review-pr/SKILL.md`'s
own Notes section, read moments earlier in this same chain — not restated here.)

---

## Integration Notes (Project-Specific)

Scope (CI-status boundary, security-routing split), severity tiers, and SCRUTINIZE-4 are defined
in full above or in `../review-pr/reference.md`'s "GH CLI" / "Review routing reference" bullets —
not repeated here. Token budget, session hooks, GH CLI submission mechanics, the routing table,
and the ledger spec: `../review-pr/reference.md`.

**Done when**: every collected finding has cleared (or been rejected by) SCRUTINIZE-4, every
Critical/Important finding has an adversarial disposition (step 3.5) or the diff cleared the
zero-findings re-hunt (step 3.6), the ledger entry is written, and the checkpoint + hand-off to
`kbg:review-pr-finish` are complete.
