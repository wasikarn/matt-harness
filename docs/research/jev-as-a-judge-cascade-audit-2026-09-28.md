# "JEV-as-a-Judge" cascade-pattern adoption audit (2026-09-28)

**Date:** 2026-09-28
**Source:** DAIR.AI "Top AI Papers of the Week" digest (llm-wiki, `raw/🥇Top AI Papers of the
Week.md`, item #5), pointing to the DAIR.AI Academy page for arXiv 2609.26550, "JEV-as-a-Judge:
Accept When Confident, Escalate When Unsure" (Li, Miao, Krishnan, Padman — Carnegie Mellon).
Fetched raw (`curl`, not WebFetch) 2026-09-28. Phase 1/2 read only the DAIR.AI curator's summary
page; after the advisor review flagged that gap, a direct `curl` of the primary arXiv abstract
(`arxiv.org/abs/2609.26550`) was pulled as a post-hoc spot-check — see criterion 1 below.
**Verdict:** Not adopted. This is the 5th scored round on TypeSafe/Jev-adjacent adoption in this
repo and the 4th to fail outright. The new angle here — a confidence-gated cheap-judge→expensive-judge
cascade, evaluated independent of the vendor — fails cleanly on **fit**, not on source fidelity:
mh's stated evidence-ordering doctrine ranks model self-confidence last among inputs, the one
cheap-tier vendor with zero install friction (Jev) was already disqualified on unrelated axes
(schema shape, vendor timeout budget) in the 2026-09-20 round, and the addressable cost saving
across every existing judge call site in this repo remains the same ~$0.15–0.50/month modeled in
that round — nowhere near the bulk-judgment volume regime the paper's 57%-of-cost result assumes.
**Score:** 5.05/10 — **FAIL** (threshold 6/10, fatal-weakness floor 40% of each criterion's own
max; confidence high — the `fit` floor trip is independently corroborated by an adversarial
re-check and the primary-source spot-check). Full criteria table: see Decision score below.

Every claim below about the source's internals is what it describes as of this read, not a
verified fact about the paper as it exists today.

## Method

2 isolated `general-purpose` analysts (Agent A: claims extraction + repo-state verification;
Agent B: fit/overlap/blast-radius), each fresh-context, neither seeing the other's output. 1
adversarial attacker (`codex exec`, `gpt-6-sol`/medium, `--sandbox read-only`, no worktree —
matches `mh:deep-audit`'s Codex-primary shape) independently re-checked both reports against
primary evidence; exit 0, schema-valid, citations passed `check-citations.py`. This pass
increments on 4 prior rounds, most recently `jev-adoption-revisit-2026-09-20.md` (scored 2.45/10)
— cited directly by both analysts and re-verified line-by-line by the attacker, not restated from
memory. A post-hoc `curl` of the primary arXiv abstract (below) corroborates the paper's core
numeric claims directly, closing most of the curator-page-only gap the first pass left open.

## Claim-by-claim: what the paper asserts vs. what this repo already has

Legend: `MATCH` = claim confirmed against primary evidence · `PARTIAL` = partially confirmed ·
`GAP` = claim not found / contradicted by primary evidence · `N-A` = not applicable to this repo.

| # | Claim | Verified? | This repo's posture | Verdict |
|---|---|---|---|---|
| 1 | JEV costs $0.044/1k judgments at 0.152s median vs GPT-6's $12.182/1.885s (~277x cheaper, 0.36% of the fee) | **Yes — observed directly against the primary source**: the arXiv abstract itself states "at 0.36% of the comparator's fee" (`curl -fsSL https://arxiv.org/abs/2609.26550` → abstract blockquote); the specific dollar figures remain curator-page-only | No LLM-judge call site in mh's own code today (all 3 `check-verdict.py` copies are pattern-matching, zero API imports) | N-A |
| 2 | Confidence-gated cascade (accept ≥0.9, else escalate) keeps 99% of GPT-6's accuracy at ~57% of its fee, on 510 held-out pairs | **Yes — observed directly** that the core assertion ("retains 99% of the comparator's accuracy at lower cost") is in the primary arXiv abstract; the specific "57%"/510-pairs detail is curator-page-only, unconfirmed against the primary text read so far | mh has zero existing confidence-gated cascade anywhere (`deep-audit`, `idea-audit`, `compliance-audit` all use *availability*-triggered fallback, never confidence-triggered) — genuinely novel mechanism, not a duplicate | PARTIAL (core claim confirmed against primary source; specific "57%" detail not) |
| 3 | Escalation threshold "did not transfer for every fallback model" — must be tuned per deployment | Author-asserted (not in the abstract; would need the full paper body) | mh's own doctrine (`docs/reference/operating-model.md:91`) independently arrived at treating confidence as the *weakest* of several ordered inputs, for the same reason (it's the one input the model controls) — directionally consistent with the paper's own caution, though the attacker found Agent B had overstated this as an outright ban rather than a weighting | PARTIAL |
| 4 | JEV is 9–20 points weaker than GPT-6 on hard derivation-checking (JudgeBench 78.6 vs 93.1), errors clustering in its own low-confidence bucket | Qualitatively confirmed against primary ("Larger gaps arise when judgments require checking a derivation... concentrated in low-confidence decisions" — arXiv abstract); the specific 9-20pt/78.6/93.1 numbers remain curator-page-only | N/A — no mh mechanism does derivation-checking via a swappable judge today | N-A |
| 5 | (Repo-state claim, not from the paper) `~/.local/share/kbg/metrics/skill-usage.jsonl` "logged nothing since" 2026-09-05, per the prior audit doc, cited by both Agent A and Agent B as still-true | Checked directly by the attacker — **false as stated**: the log has 157 rows total, 60 of them dated after 2026-09-05, latest 2026-09-28 | The removed field is the `[role:]`/orchestrate tag needed for the *routing* sub-question's revisit trigger — the log itself never stopped. Both analysts repeated a stale claim from the 2026-09-20 doc without re-checking it against the live file | GAP (analyst-repeated stale claim, corrected here) |
| 6 | Prior TypeSafe/Jev adoption verdict: 2.45/10 FAIL, from 5 weighted criteria (30/15/20/20/15, scores 2/1/3/1/6) | Yes — observed directly, re-verified by the attacker against `jev-adoption-revisit-2026-09-20.md` line-by-line | Unchanged this round; this audit evaluates a different question (the cascade *pattern*, not "adopt Jev as judge") and reaches the same FAIL by an independent path | MATCH |

## Shipped

Nothing — this is a read-only research pass. The cascade pattern fails its own fatal-weakness
floor (see below); there is no partial or pilot version worth building.

## Deliberately not shipped

- **A confidence-gated cheap→expensive judge cascade, using Jev as the cheap tier** —
  `docs/research/jev-adoption-revisit-2026-09-20.md:8-14` (Jev's schema can't populate mh's
  `evidence`/`checked[]` contract; a capability wall, not a quality gap) **and** METHODOLOGY Rule
  13 (`checked[]` non-empty required on every judge dispatch — Jev structurally cannot supply it).
  Labeled: **premise dead** (unchanged from the 2026-09-20 round; this new evidence doesn't touch
  the disqualifier).
- **A confidence-gated cascade using a cheap Claude model instead of Jev** —
  `docs/reference/haiku-decision-calls.md:57` (the Messages API exposes no logprobs/token-
  probability field, so a Claude-model cheap tier could only offer a self-reported confidence
  number) **and** `docs/reference/operating-model.md:91-93` (self-reported model confidence is
  explicitly the *weakest* of several ordered evidence inputs mh already uses for important
  decisions — building a mechanism whose entire trigger *is* that weakest input runs against the
  grain of a stated doctrine line, even though the attacker correctly notes that line stops short
  of an absolute ban). Labeled: **declined on evidence**.
- **Piloting the cascade on `mh:ideate`'s scoring pass** (the one clean seam the 2026-09-20 round
  identified) — `docs/research/jev-adoption-revisit-2026-09-20.md:23` (advisory-only, flag-gated
  pilot never built) **and** the trivial modeled saving (~$0.15–0.50/month across *every* existing
  judge call site combined) means a cascade's added build/maintain cost (two tiers + a router, on
  a doctrine-disfavored trigger signal) has no realistic payback window. Labeled: **declined on
  evidence**.

## Decision score (METHODOLOGY Rule 14)

Scale: 0–10 per criterion, matching this repo's own established convention for Jev/TypeSafe
audits (`jev-adoption-revisit-2026-09-20.md`), not the doc-template's generic /100 default.
Weights sum to 10 so the weighted total lands directly on a 0–10 scale.

| Criterion | Weight | Score | Reason |
|---|---|---|---|
| Primary-source fidelity | 4.5 | 6/10 | Largest weight — a confident total built on shaky source evidence is the exact failure mode Rule 14 exists to prevent, so this can't be diluted to parity with fit/blast-radius. Score: a post-hoc `curl` of the primary arXiv abstract confirms the paper's three core numeric claims directly (0.36% fee, gap concentrated in low-confidence decisions, 99% accuracy retention) — no longer curator-page-only. What holds it at 6, not 8-9: the granular per-benchmark numbers (RewardBench 92.2/93.5, JudgeBench 78.6/93.1, the specific "57%"/510-pairs detail) are still curator-page-only, unconfirmed against the full paper body; and the attacker caught both analysts repeating a stale, factually wrong repo-state claim (criterion 5 above — `skill-usage.jsonl` "logged nothing since" Sept 5, actually 60 rows after) without re-checking it, a real verification-rigor gap this axis also carries. An 8/10 would mean every number, not just the headline three, traced to the primary paper, with zero repeated-but-unverified repo-state claims. |
| Fit (does mh have this need) | 3.0 | 2/10 | Second-largest — a doctrine collision or a dead-on-arrival vendor constraint is the single most expensive thing to discover *after* adoption, so this outweighs blast-radius (which only matters if fit clears first). Score: mh has zero existing confidence-gated cascade (genuine gap), but: (a) the one cost-free-to-integrate cheap-tier vendor (Jev) is already disqualified on unrelated axes — schema shape, vendor timeout budget — so this pattern has no viable off-the-shelf cheap tier today; (b) mh's own Claude-model-based alternative can't produce a real confidence signal (no logprobs); (c) the addressable saving is the same trivial ~$0.15–0.50/month modeled in the prior round, nowhere near the bulk-volume regime the paper's savings claim assumes. An 8/10 here would mean a clear unmet need, meaningful stakes, and a doctrine-aligned mechanism with an available building block — none of the three hold. |
| Blast radius / reversibility | 2.5 | 7/10 | Smallest weight — this axis only prices the cost of being wrong *given* adoption already cleared fit; since fit already fails outright, a low blast-radius here can't rescue the verdict, so it's justified to weigh least. Score: the one plausible pilot (wrap `mh:ideate`'s scoring pass with a cheap pre-check that sometimes skips the expensive judge) would be small, additive, and fully reversible — never actually built, so this stays hypothetical, but the *shape* of what would be built is low-risk. A 10/10 would require zero build cost too; a 3/10 would mean touching shared gate logic with no rollback path — neither applies. |

Weighted sum: `(6/10)*4.5 + (2/10)*3.0 + (7/10)*2.5 = 2.7 + 0.6 + 1.75 = 5.05/10` (via
`scripts/_lib/weighted-score.py`, not hand-summed). Pass threshold 6/10, fatal-weakness floor 40%
of each criterion's own max. **`fit` (20%) falls below the 40% floor** — the verdict rests
cleanly on that one criterion, not on source-fidelity doubt. `primaryWeightOk: true`
(primary-source-fidelity is strictly the largest weight, as Rule 14 requires). **FAIL.**
Confidence: high (the `fit` floor trip is corroborated three ways: the attacker's independent
re-check, the primary-arXiv-abstract spot-check confirming the paper is real and the mechanism is
genuinely novel to mh, and the unchanged prior-round disqualifiers it's built on — `git show
2cac98c8 -- hooks/stop/cost-tracker.sh` for the telemetry correction, a direct `skill-usage.jsonl`
row count, and a direct read of both the curator page and the primary abstract).

## Open questions

- **Was the underlying arXiv paper's full body (methodology, exact threshold-selection
  procedure, per-benchmark tables) ever read, vs. only its abstract + DAIR.AI's summary?** — Not
  this round; the abstract spot-check confirmed the three headline numbers but not the granular
  per-benchmark figures. Revisit only if a future round specifically needs the paper's own
  methodology section, not from re-reading the same curator digest again.
- **Does a future mh judge call site reach bulk-judgment volume** (hundreds+ judge calls/month,
  not the current handful of `deep-audit`/`idea-audit` dispatches)? — Revisit the cascade *pattern*
  (vendor-agnostic) only if `~/.local/share/kbg/metrics/skill-usage.jsonl` shows that volume
  sustained over a rolling 30-day window — an observable count, not a feeling that usage "seems
  higher."
- **Does the Anthropic Messages API ever expose a real logprobs/token-probability field?** — If it
  does, the "no viable Claude-based cheap tier" disqualifier above no longer holds and the fit
  score should be re-run; check `docs/reference/haiku-decision-calls.md`'s own revisit note first,
  don't re-derive this from scratch.

<!-- Reserved: a later pass appends a dated correction here, never rewrites the sections above.
**Correction (date, mechanism):** ... -->
