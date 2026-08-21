# Judge-panel correlation vs. the tiered pipeline's single final reviewer (2026-08-22)

Targeted gap-fill for the open question in
`~/llm-wiki/wiki/ai-agents/multi-agent/src-tiered-multi-model-agent-pipeline-research.md`
(dossier 2026-08-21), whose follow-up pass leaned toward "consider a 2–3-reviewer panel vote as a
cheaper substitute for a second full top-tier pass." Two primary sources — both read directly,
one predating the dossier and missed by it — now close that question **against** the panel-vote
experiment for kbg's specific shape.

## Sources (primary, fetched 2026-08-22)

1. **"Nine Judges, Two Effective Votes: Correlated Errors Undermine LLM Evaluation Panels"**
   (arXiv:2605.29800, Apple ML Research — May 2026, *predates the dossier; missed by its
   follow-up pass*). 9 frontier LLMs from 7 model families, 3 NLI datasets, 100 human
   annotations/item: the panel yields "only about 2 independent votes' worth of information";
   ~three-quarters of nominal independence lost to correlated errors; accuracy 8–22pp short of
   the independent-voting ideal; **"the best single judge matches or outperforms the full panel
   across all conditions"**; better aggregation closes ≤11% of the deficit — the bottleneck is
   correlation, not aggregation. Caveat: NLI tasks, not code review — but the mechanism (shared
   training lineage → shared mistakes) transfers.

2. **"RoPoLL: Robust Panel of LLM Judges"** (arXiv:2606.30931). Effective jury size
   `N_eff = N/(1+(N−1)γ)`; at the typical inter-judge correlation γ≈0.45, benefit saturates
   around N=3 and "adding more judges past N≈1/γ buys essentially nothing." Panels beat a single
   strong judge only under *systematic* corruption (mode collapse, sycophancy, Byzantine judges)
   with robust aggregation — in clean conditions panels merely match single judges.

## Implication for kbg's tiered pipeline

- **A panel replacement for the Fable final pass is the worst-case shape of the jury idea here:**
  every kbg tier is Claude-family. Same-family γ is at the high end, so a 3-Claude panel's
  N_eff ≈ 1.3–1.5 votes — paying 3 review calls for barely more than one vote of information.
  The jury evidence (PoLL, LLMs-as-a-Jury) that motivated the experiment assumed cross-family
  diversity, which kbg deliberately doesn't wire (external-model write access deferred).
- **The current design is now the evidence-backed choice, not just the default:** one strong
  single final reviewer (Nine Judges: best single judge ≥ full panel), gated on
  disagreement/confidence rather than run unconditionally (TAO arXiv:2506.12482, already cited
  in `tiered-pipeline.js`'s triage log line).
- **Where RoPoLL says a panel *would* pay** — systematic judge failure like sycophancy — kbg's
  existing mitigations are deterministic, not more LLM votes: schema-forced fail-closed verdicts,
  code-counted fix caps, `ship-merge`'s own-branch severity floor.

## Verdict

Keep the triage-gated single-Fable final review. Drop the panel-vote experiment unless
cross-family judges ever become available; if it's ever revisited, RoPoLL's geometric-median
aggregation + deliberately diverse families is the only shape the evidence supports.

Wiki page not yet updated (vault writes are operator-driven — `/kbg:wiki-ingest` is the gated
path); its §"Follow-up research" panel-vote suggestion should carry this correction when folded.

In-repo applications shipped alongside this note: correlation caveat on
`skills/orchestrate/reference.md`'s Panel-vote variant clause, addendum in
`tiered-multi-model-pipeline-audit-2026-08-21.md`, and a design comment at
`scripts/workflows/tiered-pipeline.js`'s final-review triage gate.
