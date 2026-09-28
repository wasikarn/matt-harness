# "Self-Organizing Agent Teams" (SAT) adoption audit (2026-09-28)

**Date:** 2026-09-28
**Source:** DAIR.AI "Top AI Papers of the Week" digest (llm-wiki, `raw/🥇Top AI Papers of the
Week.md`, item #7), pointing to the DAIR.AI Academy page for arXiv 2609.22682, "Self-Organizing
Agent Teams Learn to Reason Together" (Pappu, Suzgun, Kwon, Bianchi, El, Kochenderfer, Cao, Zou —
Stanford/Together AI/Emory Goizueta). Both the DAIR.AI curator page and the primary arXiv abstract
page were fetched raw (`curl`, not WebFetch) 2026-09-28, this time deliberately — the prior round
(JEV-as-a-Judge, `jev-as-a-judge-cascade-audit-2026-09-28.md`) only read a curator page and had to
be corrected after the fact.
**Verdict:** Not adopted. The paper describes a fixed AI-agent team that learns a reusable
collaboration strategy (roles, phase order, participation, information flow) from a small number
of past problems, then freezes it and applies it unchanged to new tasks. mh already runs this
exact outer loop — with a **human** as the learner, not the model: every fixed dispatch shape in
`ideate`/`idea-audit`/`deep-audit` is a strategy a person mined from a specific past incident (the
44→105-agent runaway, the retired `orchestrate` skill's cost data) and froze into a skill file.
Adopting the paper's actual mechanism — the team observing its own outcomes and revising its own
organization without a human re-authoring the skill — is not a gap to fill; it is the specific
"orchestration layer of its own" `docs/reference/operating-model.md` states mh deliberately does
not build, regardless of whether the learning step runs autonomously or is triggered by a person
(the paper's own learning step is itself offline/human-run between sessions, not something the
model launches — see the attacker's pushback on claim #6 below). ADR 0011 is adjacent evidence of
the operator's low appetite for crossing autonomy-adjacent invariants, not a precedent proven to
be directly on point. mh's own telemetry can't bootstrap it anyway: no schema field records which
roles/phases ran or whether the result was correct, only coarse invocation counts and cost.
**Score:** 5.0/10 — **FAIL** (threshold 6/10, fatal-weakness floor 40% of each criterion's own
max; confidence high — the `fit` floor trip rests on a live ADR and two operating-model.md lines
re-verified directly by the adversarial attacker, not just asserted by the fit analyst).

Every claim below about the source's internals is what it describes as of this read, not a
verified fact about the paper as it exists today.

## Method

2 isolated `general-purpose` analysts (Agent A: claims extraction + repo-state verification;
Agent B: fit/overlap/blast-radius), each fresh-context, neither seeing the other's output. Agent
A was given both the DAIR.AI curator page and the primary arXiv abstract page (a direct `curl` of
`arxiv.org/abs/2609.22682`) and told explicitly to distinguish claims corroborated in the primary
text from curator-only restatements. 1 adversarial attacker (`codex exec`, `gpt-6-sol`/medium,
`--sandbox read-only`, no worktree) independently re-checked both reports; exit 0, schema-valid,
citations passed `check-citations.py`. The attacker caught one real Agent A error (see claim #4
below) and pushed back — correctly, on re-check — against two of Agent B's doctrine-collision
claims for being stronger than the primary source alone can support (claims are true on this
repo's own doctrine text, just not provable from the paper's abstract).

## Claim-by-claim: what the paper asserts vs. what this repo already has

Legend: `MATCH` = claim confirmed against primary evidence · `PARTIAL` = partially confirmed ·
`GAP` = claim not found / contradicted by primary evidence · `N-A` = not applicable to this repo.

| # | Claim | Verified? | This repo's posture | Verdict |
|---|---|---|---|---|
| 1 | Core mechanism: fixed team learns reusable roles/phases/participation/information-flow strategy from prior collaborations, transfers unchanged to new tasks | **Yes — observed directly against the primary arXiv abstract** ("fixed teams of AI agents that learn reusable strategies from prior collaborations to organize roles, conversational phases, participation, and information flow") | mh runs the same outer loop today, human-in-the-loop: every fixed wave shape in `ideate`/`idea-audit`/`deep-audit` was mined from a specific past run's outcome and frozen into a skill file by a person (`skills/workflow/ideate/references/provenance.md:8-20`, the 44→105-agent runaway) | MATCH (mechanism exists here — with a human, not a model, as the learner) |
| 2 | Headline results: 66.7% team accuracy vs 48.8% strongest member, 58.7% compute-matched, 59.0% perfect router; beats router by 13.4 points on AIME 2026 | **Yes — observed directly against the primary arXiv abstract** (exact figures present verbatim) | N-A — no mh mechanism runs comparable multi-model benchmark tasks | N-A |
| 3 | Demonstrability (can the team recognize correct reasoning once it appears) tracks team gain, Spearman ρ=0.90 (p=0.005) across 8 benchmarks | **Yes — observed directly against the primary arXiv abstract** (exact figure present verbatim) | mh's own workflows split cleanly on this axis: `deep-audit`'s validator/fixer chain is high-demonstrability (gated on `weighted-score.py`/`check-verdict.py` exit codes); `ideate`'s novelty/viability/fit scoring is low-demonstrability, and `ideate/SKILL.md:125` already names this failure mode ("Judge as ground truth") without using the paper's term | MATCH |
| 4 | Specific model lineup (o3-mini/Sonnet 4/DeepSeek-V3, Gemini-2.5-Flash/Llama-4-Maverick/GPT-4.1), benchmark names (AIME 2024, GPQA Diamond), certificate+judge mechanism, per-benchmark gains (29.0pt/2.7pt), and the 71.2% AIME-2026 figure | Mixed — most of this is **Author-asserted, curator-page-only** (confirmed absent from the primary abstract by direct string search: `python3 -c '"AIME 2024" in ... arxiv-2609.22682.html'` → `False`, similarly for "certificate", "judge", "29.0", "2.7"). The attacker separately caught that Agent A had mistakenly tagged the **71.2% AIME-2026 figure** as primary-source-confirmed when it is DAIR-page-only (`"71.2" in arxiv-2609.22682.html` → `False`) | N-A | PARTIAL (curator-only, not contradicted — one analyst-tagging error, corrected here; the rest correctly flagged as curator-only by Agent A itself) |
| 5 | mh has no existing telemetry rich enough to learn a collaboration strategy from — no role/phase/participation/outcome fields anywhere | **Yes — observed directly**, re-verified by the attacker: `skill-usage.jsonl`'s live schema is `{ts, session_id, skill, plugin}`; `costs.jsonl` adds cost/token fields but no organization or correctness column; `hooks/session/skill-usage-telemetry.sh:8` states this explicitly | This is the load-bearing structural gap: adopting SAT's mechanism needs (organization, outcome) pairs mh doesn't record today, confirmed by both analysts and the attacker independently | MATCH (repo genuinely lacks this — an instrumentation gap, not a design choice mh could just flip) |
| 6 | mh already declined a smaller, adjacent step — an autonomous/scheduled self-improvement loop (ADR 0011, rejecting scheduled `recursive-improve`) — to protect a "no-model-self-launch" invariant | **Yes — observed directly**: `docs/research/adr-0011-scheduled-recursive-improve-invocation.md:2-3` — "Status: 🔴 Rejected... accepting this is the first-ever crossing of the no-model-self-launch invariant..." **but the attacker correctly flagged that this doesn't prove a collision with SAT specifically**: the paper's own learning step is offline/human-run between sessions ("apply unchanged to unseen problems"), not a model launching itself, so ADR 0011's exact invariant isn't shown to be crossed by the paper's mechanism as described | PARTIAL (ADR 0011 shows low operator appetite for autonomy-adjacent invariants generally — real, relevant context — but is not itself proof of collision; `operating-model.md:104`'s "no orchestration layer of its own" line is the claim that actually holds regardless of who triggers the learning step, since a learned-strategy subsystem is that layer either way) |

## Shipped

Nothing — this is a read-only research pass. Fit fails outright; there is no partial or pilot
version of the paper's actual mechanism worth building against a live rejected-ADR precedent.

## Deliberately not shipped

- **A mechanism that learns and rewrites mh's own multi-agent dispatch shape across runs, model-
  triggered or not** — `docs/reference/operating-model.md:104-105` ("No orchestration layer of its
  own: dispatch shape is one page (`spawn-brief.md`); Claude Code's native Agent tool does the
  rest") — a learned-strategy subsystem is that layer regardless of who triggers the learning
  step. ADR 0011 (rejecting scheduled `recursive-improve`) is adjacent supporting context on the
  operator's low appetite for autonomy-adjacent invariants, not itself proof this collides (see
  claim #6's PARTIAL verdict). Labeled: **premise dead** — this isn't an unbuilt feature, it's the
  specific thing mh's operating doctrine names as intentionally absent.
- **Adding an outcome/organization-shape field to `skill-usage.jsonl`/`costs.jsonl` as a first
  step toward this** — no doctrine objection to the telemetry addition itself, but
  `docs/research/orchestrate-cost-optimization-2026-09-03.md`'s TL;DR item 2 already flagged this
  exact gap a month earlier for a *different, already-deleted* skill (`orchestrate`) and it was
  never built even for that narrower, already-approved-in-principle case. Labeled: **deferred** —
  worth doing on its own merits (better cost/effectiveness visibility) but has no realistic
  payback tied to this specific idea, since the mechanism it would feed is premise-dead above.

## Decision score (METHODOLOGY Rule 14)

Scale: 0–10 per criterion, matching the convention set in this repo's most recent Jev-adjacent
audit (`jev-as-a-judge-cascade-audit-2026-09-28.md`). Weights sum to 10 so the weighted total
lands directly on a 0–10 scale.

| Criterion | Weight | Score | Reason |
|---|---|---|---|
| Primary-source fidelity | 4.5 | 7/10 | Largest weight — same rationale as the prior round: a confident total built on shaky source evidence is the exact failure Rule 14 exists to prevent. Score: unlike the prior round, the primary arXiv abstract was fetched up front, and every headline claim (mechanism, the 5 core benchmark numbers, the Spearman correlation) was confirmed directly against it, not just a curator's restatement. What holds it at 7, not 9-10: the attacker caught one real analyst error — Agent A tagged the 71.2% AIME-2026 figure as primary-confirmed when a direct string search shows it's curator-page-only — and the granular model lineup / certificate mechanism / per-benchmark gains remain curator-only, correctly flagged as such by Agent A itself. |
| Fit (does mh have this need) | 3.0 | 2/10 | Second-largest — a live rejected-ADR precedent directly on point is the cheapest possible way to discover this is dead on arrival, so it can't be diluted to parity with blast-radius. Score: mh already meets the underlying need (learning better multi-agent organization from past outcomes) via a human-in-the-loop process that's run repeatedly and successfully (the `ideate` wave-shape history). Adopting the paper's actual mechanism — the model learning and revising its own organization — isn't an open gap, it's the specific thing `operating-model.md` names as deliberately absent, and ADR 0011 already rejected a strictly smaller crossing of the same invariant. On top of that, mh's telemetry can't even bootstrap a compliant variant (no outcome data). A 8/10 would mean a genuine unmet need with no doctrine conflict and available data — none of the three hold. |
| Blast radius / reversibility | 2.5 | 5/10 | Smallest weight — this only prices the cost of being wrong given fit already cleared, and fit already fails outright, so it can't rescue the verdict. Score: split down the middle deliberately. The safe, realistic incremental step (add an outcome field to telemetry, per Agent B) is small and fully reversible — a 8-9/10 shape. But the paper's actual mechanism, if built as described (autonomous cross-run strategy rewriting), would cross a stated bright-line invariant mh has already declined to cross once — a one-way doctrinal breach that a code revert doesn't undo, a 2-3/10 shape. 5/10 reflects that bifurcation rather than picking one reading as if it were the only one considered. |

Weighted sum: `(7/10)*4.5 + (2/10)*3.0 + (5/10)*2.5 = 3.15 + 0.6 + 1.25 = 5.0/10` (via
`scripts/_lib/weighted-score.py`, not hand-summed). Pass threshold 6/10, fatal-weakness floor 40%
of each criterion's own max. **`fit` (20%) falls below the 40% floor** — the verdict rests
cleanly on that one criterion. `primaryWeightOk: true` (primary-source-fidelity is strictly the
largest weight, as Rule 14 requires). **FAIL.** Confidence: high, resting on two independently
verified pillars, not on ADR 0011 alone: `operating-model.md:104`'s "no orchestration layer of its
own" line (holds regardless of who triggers the learning step) and the confirmed telemetry gap
(no role/phase/outcome data to learn from). The attacker correctly pushed back on treating ADR
0011 and the maker≠checker framing as proven collisions from the abstract alone — that pushback is
folded into claim #6's PARTIAL verdict and the fit reason above, not overridden.

## Open questions

- **Would a purely offline, single-round version of this** (a person, not the model, reviews N
  past runs' outcomes and manually authors a revised skill file — i.e., exactly what mh already
  does) **benefit from formalizing the "mine past outcomes into a frozen strategy" step as a
  repeatable process/checklist**, separate from any model-autonomous mechanism? — Not scored this
  round (out of scope: the live decision was the paper's actual autonomous mechanism). Revisit
  only if a future session wants a lighter, purely-human tool for the `orchestrate-cost-
  optimization-2026-09-03.md`-style analysis, not from re-reading this paper again.
- **Does ADR 0011 or ADR 0009's retained invariants ever get revisited?** — Revisit this audit's
  `fit` score only if either ADR is reopened/superseded by a later, dated decision — not from
  further reading of this or any other paper about agent self-organization.

<!-- Reserved: a later pass appends a dated correction here, never rewrites the sections above.
**Correction (date, mechanism):** ... -->
