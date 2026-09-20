# Jev/TypeSafe adoption revisit — matt-harness, 2026-09-20

Fourth pass on the same question. Prior three rounds (`typesafe-ai-system-one-jev-2026-09-18.md`
and its two addenda) settled "no adoption" on a redundancy argument: mh already has
`codex exec --output-schema`. User explicitly requested a revisit ahead of the process's own
stated trigger (see §4) after a new infographic prompted deeper drill-down. This pass ran 5
independent senior-lens agents in parallel against live primary sources (TypeSafe's own docs,
mh's actual code, git history, and live cost/skill-usage logs) plus a same-day fact-check
addendum on 9 new numeric claims (7 confirmed, 1 misattributed, 1 unsourced — see the base doc's
"Additional benchmark claims fact-check — 2026-09-20" section).

## Rule 14 scored verdict

Decision: should matt-harness adopt Jev/TypeSafe anywhere in its own code. Score 0–10 per
criterion (10 = strongly supports adoption), weighted.

| Criterion | Weight | Score | Reason |
|---|---:|---:|---|
| Architecture/structural fit | 30% | 2 | Jev is a pure typed function (state+questions → typed answers, no tools, no evidence field). All 3 of mh's existing model-judgment schemas (`checker`, `attacker`, `verifier`) require a free-text `evidence`/`checked[]` field with `minItems: 1` — a vacuous-accept guard already added after a real incident. Jev cannot populate any of them; this is a capability wall, not a quality gap. Its one genuine edge (N questions over one shared state, near-free marginal cost) has no urgent unmet need in mh today. *A 2 looks like: disqualified from every existing call site by a hard structural requirement, with one narrow theoretical edge and no current consumer.* |
| Cost/ROI at current volume | 15% | 1 | Modeled addressable saving across every candidate decision point (idea-audit, ideate, deep-audit, orchestrate) is ~$0.15–0.50/month at current usage; mh's gates are 100% deterministic bash/regex with zero LLM calls, so there's nothing to swap there at all. Integration cost (typed client, auth, schema mapping, fallback handling, testing against an early-access API) is a multi-hour build with no realistic payback window. *A 1 looks like: cents/month of addressable saving against a multi-hour build and a new credential to manage.* |
| Security / vendor-trust fit with mh's gate doctrine | 20% | 3 | TypeSafe has real legal docs (DPA, no-training-on-customer-data architecture) — better-documented than assumed — but open-ended default retention and no third-party security certification. The disqualifying issue is structural, not trust: Jev's SDK defaults to a 120s timeout with an ~8-concurrent rate ceiling, against mh's synchronous ~8-second `PreToolUse` gate budget and explicit fail-closed doctrine. A vendor outage would either block the operator's own workflow or silently defeat the gate. Advisory-only use outside `gate:*` is conditionally fine. Would also be mh's first-ever outbound network dependency of its own code (Codex is a locally-authed CLI, not an in-repo key). *A 3 looks like: a legitimate, documented vendor whose product structurally cannot go where adoption would matter most.* |
| Evidence sufficiency to justify revisiting now | 20% | 1 | Zero load-bearing new facts. All 7 newly-confirmed infographic claims (batching math, Google Flights latency, Every's 777-checks case study, mobile-Jev demo, legal retrieval case study, the Noul primitive, current pricing) establish that Jev is real and accurately marketed — already conceded on 2026-09-19. The 2 that failed (193x/444x misattribution, unsourced "steal the system" framing) cut against the vendor. The process's own revisit trigger for the routing sub-question (≥10 orchestrate-tagged sessions) sits at **1** and is currently *unreachable*: the `[role:]` tagging needed to count it was deliberately removed in commit `2cac98c8` (v1.1.0, 2026-09-05), and `skill-usage.jsonl` has logged nothing since that date while cost logging continued. The trigger cited to open this revisit was also written by the orchestrator in the same pass that then evaluated it — a weak independent signal, flagged for the record. *A 1 looks like: the cited trigger for reopening a settled decision turns out to be self-generated and its underlying counter was intentionally disabled two weeks earlier.* |
| Concrete pilot viability (is there a safe place to actually try it) | 15% | 6 | One genuinely clean candidate exists: `mh:ideate` Phase 2's novelty/viability/fit scoring (`skills/workflow/ideate/scripts/rank.py`'s existing stdin contract). Real technical hook, not just cost/speed: Jev's parallel non-autoregressive sampling would make the skill's existing anchoring guard ("score every idea before ranking any") *structurally* true instead of merely instructed. Full dual-run, advisory-only, `MH_JEV_PILOT`-gated design specified with kill criteria, never gate-blocking. *A 6 looks like: a real, low-blast-radius seam with a genuine narrow argument — a "could," not a "should."* |

**Weighted score: 0.30(2) + 0.15(1) + 0.20(3) + 0.20(1) + 0.15(6) = 2.45 / 10 → FAIL** (bar for
"adopt or revisit now" set at ≥6/10).

**Confidence: high.** Four of five independent lenses converged on concrete, cited, empirical
evidence (grep results, git history, live logs, primary-source docs fetched this session). The
one lower-confidence lens (cost/ROI) was low-confidence specifically because of an acknowledged
mh telemetry gap, not because of a close call — and that gap affects precision, not direction.

## Verdict

**No adoption — reaffirmed a 4th time, on stronger and more specific grounds than the prior
three rounds' "redundant with `codex exec --output-schema`" framing**, which the architecture
lens found was itself imprecise: these are two different classes of tool (agentic reporter that
must show evidence vs. pure typed function that cannot) that merely share one shallow property.

Two items are worth carrying forward, independent of the adoption verdict:

1. **A genuinely separate, unresolved question**: the `skill_suggestion` cookbook's claimed
   16.8%→7.3% wrong-skill-load reduction is Jev-adjacent but not an adoption argument — it opens
   whether *mh's own* skill-routing wrong-load rate is worth measuring at all (12 skills today).
   No Jev dependency; gated on mh choosing to measure its own baseline first.
2. **A real, unrelated process finding**: the `[role:]`/orchestrate-session instrumentation that
   `docs/reference/spawn-brief.md:7` still emits was deliberately removed from `cost-tracker.sh`
   in v1.1.0 (commit `2cac98c8`, 2026-09-05), making the ≥10-orchestrate-session threshold
   `orchestrate-cost-optimization-2026-09-03.md` set for the *routing* sub-question permanently
   unreachable until someone re-instruments it. This is a documentation/instrumentation drift
   issue on its own merits, unrelated to Jev — not actioned here, flagged for whoever owns that
   doc next.

If the ideate-scoring pilot is ever wanted, the full blueprint (state/questions shape, adapter
script interface, file list, build order, dual-run design, kill criteria, and why every other
candidate in the repo is disqualified) is preserved in this session's transcript and can be
regenerated on request — not written to a separate file here since the verdict is not to build it.

## Sources

- `docs/research/typesafe-ai-system-one-jev-2026-09-18.md` (base + 3 addenda, including today's
  "Additional benchmark claims fact-check — 2026-09-20")
- TypeSafe live docs, fetched 2026-09-20: `concepts/system-one`, `api`, `primitives/{choice,score,noul}`,
  `confidence`, `models` (pricing), `typesafe.ai/blog/introducing-system-one-models-and-jev`,
  `typesafe.ai/legal/privacy-policy`, `typesafe.ai/legal/data-processing`,
  `introduction/machine-learning-primer`
- mh repo: `docs/reference/operating-model.md`, `hooks/gates/*`, `hooks/stop/cost-tracker.sh`,
  `scripts/_lib/weighted-score.py`, `skills/review/{deep-audit,compliance-audit}/`,
  `skills/workflow/{idea-audit,ideate}/`, `agents/ideate-critic.md`,
  `docs/research/orchestrate-cost-optimization-2026-09-03.md`,
  `~/.local/share/kbg/metrics/{costs,skill-usage}.jsonl`, `git log -S"role" -- hooks/stop/cost-tracker.sh`
