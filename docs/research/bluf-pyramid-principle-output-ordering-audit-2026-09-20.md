# BLUF / Pyramid Principle output-ordering adoption audit (2026-09-20)

**Date:** 2026-09-20
**Source:** Pasted text, 79 lines — a Thai social-media post arguing that data presentations to
executives should use the "Pyramid Principle" / "Bottom-Line-First" (BLUF) structure: lead with
the decision, then key insights, then push detailed data to an appendix. Ends with a promo for a
"Data-Driven Decision Making for Business Leaders" workshop. No URL, no author byline; saved
verbatim from the user's pasted message, not fetched.
**Verdict:** Adopt narrowly, reject the broad framing. The underlying principle (put the
decision-relevant information where the reader's eye actually lands first) is real, well-attested,
and matt-harness already implements it in practice — but inconsistently across two different
reading media, and the *rationale* for that split had no stated rule anywhere. The fix is not
"make everything verdict-first": the adversarial pass proved that would break four agents whose
flat "verdict last" shape is deliberate and already correct for a scrolling terminal. The real, narrow
gap was (1) the medium-based split's rationale had no stated rule anywhere, so a new skill/agent
had no way to pick the right one on purpose — closed by adding
`docs/reference/agent-authoring-conventions.md` item 9, and (2) `idea-audit`'s own artifact
template buried the Rule-14 numeric verdict at the bottom of a top-down-read document with no
medium-based excuse for doing so — closed by adding a `**Score:**` line to
`doc-template.md`'s header, without moving the full table. Two shipped fixes, not one.
**Score:** 72/100 — **PASS** (threshold 65; confidence high). Full criteria table: see Decision
score below.

**Correction (2026-09-21, `mh:deep-audit`, fresh-context Codex checker on the shipping commit):**
this artifact had already committed one more overclaim past the two the plan-review round caught:
row 6 and the "Deliberately not shipped" section counted `agents/plan-reviewer.md` as a 5th
verdict-last agent. It isn't — `plan-reviewer.md:183`'s `verdict:` field sits mid-block, followed
by 4 more fields, a structured multi-field report, not this repo's flat verdict-last shape (now
scoped out explicitly in `agent-authoring-conventions.md` item 9). The real cohort is 4 agents,
corrected in place below. Also fixed: row 8's `doc-template.md` line citations were stale by 2
lines against this same commit's own template edit, and this artifact lacked the `**Score:**`
header line its own fix now mandates for every future artifact — added above. Added the Score
line directly (a structural backfill, not a correction of a wrong claim); corrected the
"five"/"5"-agent count and the stale citation in place rather than appending a second full
paragraph, since both are small factual fixes, not a reinterpretation of the findings.

Every claim below about the source's internals is what it describes as of this read, not a
verified fact about the source as it exists today or in the future.

## Method

2 isolated `general-purpose` agents (Phase 1: Agent A read the saved source and checked its
attribution/technique claims; Agent B read this repo's live output conventions), then 1 adversarial
attacker (`codex exec`, `gpt-5.6-sol`, effort `medium`, sandbox `read-only`) independently
re-checked both reports against primary evidence. No prior audit exists on this topic — checked
`docs/research/` and this repo's memory index before dispatch, no hit beyond generic
false-positive word matches. Codex primary succeeded: exit 0, output validated by
`check-verdict.py` (exit 0) and `check-citations.py` (exit 0) — no fallback needed.

## Claim-by-claim: does matt-harness already do this, and where

Legend: `MATCH` = claim confirmed against primary evidence · `PARTIAL` = partially confirmed ·
`GAP` = claim not found / contradicted by primary evidence · `N-A` = not applicable to this repo.

| # | Claim | Verified? | This repo's posture | Verdict |
|---|---|---|---|---|
| 1 | "Pyramid Principle" is a real technique (Barbara Minto, ex-McKinsey) | Yes — observed directly | N-A (external fact, not about this repo) | N-A |
| 2 | "Bottom-Line-First" (BLUF) is a real technique (U.S. Army AR 25-50 origin) | Yes — observed directly | N-A | N-A |
| 3 | The post treats Pyramid Principle and BLUF as the same technique | Author-asserted (attacker confirmed the post's own framing at source line 23, 31; the two are related but not identical frameworks) | N-A | N-A |
| 4 | Executives prefer conclusion-first structuring in time-limited meetings | Author-asserted, no data/study cited (attacker confirmed no supporting evidence at source lines 19-21) | `skills/review/deep-audit/SKILL.md:243-249` acts on this assumption as prose doctrine ("line one is the Final Verdict"), but the mechanical grader contract (`evals/deep-audit-planted/graders/contract.md:3`, `(^|\n)...Final Verdict...` with `match: contains`) matches the token at the start of *any* line, not specifically line one — position is not actually enforced | PARTIAL (repo assumes and states this; enforcement is weaker than first claimed) |
| 5 | Structure: decision first, then key insights, then data as appendix | Yes — observed directly, describing the prescription only | Split posture — see rows 6-7 | PARTIAL |
| 6 | Applying "verdict/decision first" would require no agent-file edits (Agent B's original claim) | GAP — attacker found this false | `agents/type-design-analyzer.md:85`, `blind-spot-hunter.md:187`, `test-gap-analyzer.md:73`, `silent-failure-hunter.md:192` all explicitly end with "one-line verdict" as their **last** line, by design — 4 agents, this cohort's real count. `agents/plan-reviewer.md:183`'s `verdict:` field is mid-block (after `plan_source`/`findings`/`cleared_decoys`/`top_blockers`, before `confidence`/`not_reviewed`/`verdict_movers`/`revisit_if`) — a structured multi-field report, not this flat verdict-last shape; a later deep-audit pass (2026-09-21) caught this row over-counting it as a 5th | GAP |
| 7 | Verdict-last in those agents is a real convention worth keeping, not an oversight | Yes — observed directly (independently confirmed by reading all 4 files) | The practice is real and consistent, but its rationale had no stated rule anywhere in this repo — `agent-authoring-conventions.md` item 8 documents closed-vocabulary *status tokens*, not ordering, and this repo's `CLAUDE.md` has no equivalent to the operator's personal dotfiles' plan-mode "concrete steps last" clause (row 11). Now written down at `agent-authoring-conventions.md` item 9, shipped in this pass | MATCH (deliberate, correct as-is; rationale now documented) |
| 8 | `idea-audit`'s own artifact template already puts the numeric Rule-14 verdict last (Agent B's original claim, "sits last") | PARTIAL — attacker found this overstated: pre-fix, the numeric score was at `doc-template.md:46-54`, closer to the middle, with `## Open questions` still after it at line 56-58. Post-fix (see Shipped), the same section is at `doc-template.md:48-56` — the `**Score:**` header line above closes the gap without moving it | Same document is read top-down (a `docs/research/*.md` file, not a terminal stream) — no medium-based reason exists for burying the Rule-14 number below the findings table the way `deep-audit` does not | GAP pre-fix, closed post-fix |
| 9 | `docs/reference/spawn-brief.md` mandates verdict-first only for the validator/re-validator role | Yes — observed directly, attacker-confirmed at `spawn-brief.md:23-26` (builder/fixer: no shape at all) vs. `:28-31` (validator: `{pass, ...}` leads) | Builder and research roles have no return-shape mandate either way | GAP (silent, not wrong) |
| 10 | `docs/METHODOLOGY.md` Rule 14 requires scoring components but no stated order | Yes — observed directly, attacker-confirmed at `METHODOLOGY.md:32-34` | No ordering rule exists to violate or to point new skills at | GAP |
| 11 | This repo's own `CLAUDE.md` has no "Plan mode output shape" section (only the global dotfiles `CLAUDE.md` does) | Yes — observed directly, attacker-confirmed via `rg` across both files: only `~/.claude/CLAUDE.md:77,81` match, nothing in this repo's `CLAUDE.md:1-80` | Confirms row 7's rationale wasn't written anywhere *in this repo* before this pass — closed by `agent-authoring-conventions.md` item 9, not by relying on the operator's personal config | N-A (informational; gap now closed by item 9) |

## Shipped

Two fixes, in a plan-mode follow-up pass to this audit (2026-09-21, plan approved by Codex
plan-review after 4 rounds):
- `skills/workflow/idea-audit/references/doc-template.md` — added a `**Score:**` line to the
  header (total/PASS-FAIL/confidence), closing row 8's gap without moving `## Decision score`.
- `docs/reference/agent-authoring-conventions.md` — added item 9, "Verdict position follows the
  reading medium," stating the split's rationale explicitly for the first time in this repo,
  closing rows 7/9/10/11's gap.

## Deliberately not shipped

- **A repo-wide "all output must be verdict-first" convention or lint check** —
  `agents/type-design-analyzer.md:85`, `agents/blind-spot-hunter.md:187`,
  `agents/test-gap-analyzer.md:73`, `agents/silent-failure-hunter.md:192` and doctrine anchor
  Rule 1 ("blast radius" — a blanket rule here would force rewriting 4 already-correct,
  deliberately-verdict-last agent output shapes for no behavioral gain, plus break
  `agents/requirement-analyst.md:139`'s and `agents/plan-reviewer.md:183`'s own structured
  multi-field verdict placement — see `agent-authoring-conventions.md` item 9's scope note).
  Labeled: **declined on evidence** — the adversarial pass falsified the premise that a uniform
  rule has zero cost.
- **Reusing `hooks/gates/subagent-verdict-gate.py` as a position-enforcement mechanism** (Agent
  B's original proposal) — `hooks/gates/subagent-verdict-gate.py:126-133` only validates verdict
  *content* (vacuous/self-contradictory `pass`), not verdict *position* in the text; the gate has
  no logic to check where in a report a verdict token appears. Labeled: **premise dead** — the
  named mechanism doesn't do the job it was proposed for; a real enforcement path would need new
  logic, not reuse.

## Decision score (METHODOLOGY Rule 14)

| Criterion | Weight | Score | Reason |
|---|---|---|---|
| Primary-source fidelity | 45 | 7/10 | External technique claims (Minto/Pyramid Principle, BLUF/AR 25-50) fully corroborated. But the *fit* analysis that actually drives the adoption decision had 2 of 4 attacker findings materially revise it (blast radius was understated; the proposed enforcement mechanism doesn't do what was claimed) — a first-pass-only read would have shipped a wrong blast-radius conclusion. A 10 would mean zero attacker corrections; a 3 would mean the core external claims themselves were false. |
| Fit | 30 | 6/10 | A real, narrow need exists (row 8's inconsistency, rows 9-10's silence), but the broad need the research agents originally sized ("formalize verdict-first repo-wide") is the wrong-sized ask — a correctly-scoped version is much narrower than proposed. A 9 would mean the gap matched the proposal's scope exactly; a 2 would mean no real gap existed at all. |
| Blast radius / reversibility | 25 | 9/10 | For the correctly-scoped fix (state the medium-based rule in prose; reorder one template section), the change touches 1-2 files, is plain markdown, and is trivially reversible. A 10 would require zero files touched; a 4 would mean touching gate/hook code with behavioral effects. |

Weighted sum: (7×45 + 6×30 + 9×25) / 100 = (315 + 180 + 225) / 100 = **72/100**. Pass threshold
65, fatal-weakness floor 40% per criterion — no criterion fell below floor (lowest is Fit at 60%
of its own max); source side was not entirely `insufficient evidence`, so the floor did not trip.
**PASS — for the narrow scope only** (see Verdict above; the broad framing the request opened
with does not clear this bar and is declined above). Confidence: **high** (2 independent analysts,
1 adversarial re-check with 10 independently-verified citations, all citations passed mechanical
shape validation, and this audit independently re-verified the attacker's own most load-bearing
citations by reading the 4 named agent files directly rather than trusting the attacker's report).
The follow-up implementation plan itself went through 4 rounds of independent Codex plan-review,
which caught this artifact's own row-7 overclaim (see Shipped) before it shipped — a second,
independent adversarial pass beyond Phase 2's attacker, on the same source.

## Open questions

- ~~Should the medium-based rule get written into `agent-authoring-conventions.md` or
  `METHODOLOGY.md` Rule 14?~~ Resolved and shipped: `agent-authoring-conventions.md` item 9 —
  `METHODOLOGY.md` had only 376 bytes of headroom under its 4096-byte pre-commit cap, too little
  for a full rule with rationale, so the conventions file (no length cap) was the right home.
- ~~Is `doc-template.md`'s numeric-verdict placement worth moving?~~ Resolved and shipped: not
  moved, duplicated as a `**Score:**` header line instead — moving would have staled
  `skills/workflow/idea-audit/SKILL.md:264,336-341,367` and diverged from 4 already-shipped
  artifacts.
- Do `spawn-brief.md`'s builder/research roles need an explicit return-shape mandate at all, or is
  their current silence intentional (free-form roles by design)? Revisit only if a real incident
  surfaces from a builder/research return that was hard to parse because of ordering — not from
  further reading of this source.
