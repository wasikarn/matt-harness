# TypeSafe AI: "System One Models" and Jev — source and claims check

Date: 2026-09-18. Method: fetched the source blog post
(`typesafe.ai/blog/introducing-system-one-models-and-jev`) plus TypeSafe's own docs
(`docs.typesafe.ai`), its public GitHub repo, the InstructGPT paper on arXiv, the company's
funding press release, and one independent news article (The Register), then WebSearched for
corroboration and for prior art on the terms used. No `qmd`/llm-wiki hits on this topic (new,
Sep 2026 launch).

## TL;DR

- **Not fabricated.** TypeSafe AI is a real, funded company; the founder's credentials check out;
  the product has real docs, a real (if early-access) API, and an open-source adapter repo. This
  is a genuine product launch, not a hoax or an invented domain.
- **But the headline performance numbers are 100% vendor self-reported.** Speed ("70–500ms",
  "40x–200x faster"), the Pareto-frontier benchmark chart, and the "0% hallucination" figure all
  come from TypeSafe's own blog/docs. No independent benchmark, academic paper, or third-party
  reproduction was found anywhere. The product is early-access/waitlisted, so outsiders can't
  test it yet either. The blog post itself concedes this ("our published evals are generally run
  from our laptops"; "we can't prove it isn't subsidized").
- **"RLCD" collides with an existing, unrelated method.** Yang et al.'s "RLCD: Reinforcement
  Learning from Contrast Distillation" (Meta/Berkeley, ICLR 2024) already uses this exact
  acronym for a different LLM-alignment technique. TypeSafe's blog does not acknowledge the
  collision, and TypeSafe has published no paper or technical spec for its own "Reinforcement
  Learning for Calibrated Decisions" beyond the name and a one-line description.
- **"System 1" framing for AI is not new.** Yoshua Bengio used the same Kahneman dual-process
  metaphor at NeurIPS 2019 to argue deep learning needed to move *toward* System 2. TypeSafe is
  making the opposite bet — shipping a System-1-only, non-generative model — right as the
  industry's dominant recent trend (OpenAI's o1/o3 "reasoning models") went further into System 2.
  That contrast is the most substantive framing point in the post; it's real, just not new
  vocabulary.
- **The "co-inventor of RLHF/ChatGPT" framing is press inflation.** Founder Diogo Almeida is a
  confirmed co-author (4th of 20) on the InstructGPT paper, which drove ChatGPT's post-training
  recipe. RLHF itself predates that paper (Christiano et al. 2017, OpenAI/DeepMind). "Co-author of
  the paper behind ChatGPT" is accurate; "co-inventor of RLHF" is a secondary-press upgrade the
  primary source doesn't itself support.

## 1. Is the source legitimate?

| Question | Finding | Source |
|---|---|---|
| Who publishes typesafe.ai? | TypeSafe AI, a real startup founded by Diogo Almeida, Erik Gafni, Sasha Sheng | Company site itself; [LinkedIn](https://www.linkedin.com/company/typesafe-ai), [Ashby jobs page](https://jobs.ashbyhq.com/typesafe-ai) |
| Is it funded / real? | $40M seed led by DCVC, announced via the company's own wire release | [BusinessWire](https://www.businesswire.com/news/home/20260915525333/en/TypeSafe-AI-Emerges-From-Stealth-With-$40M-in-Funding-With-New-Model-for-Composable-AI) (primary — company-issued), syndicated by [HPCWire/AIwire](https://www.hpcwire.com/aiwire/2026/09/16/typesafe-ai-emerges-from-stealth-with-40m-in-funding-with-new-model-for-composable-ai/), Yahoo Finance, Morningstar |
| Independent (non-PR-rewrite) press coverage? | Yes for The Register — fetched and read in full. Thomas Claburn's piece has its own headline/framing, but on the numbers it **restates TypeSafe's own demo figures without independently reproducing them**: it quotes "Jev returning a response in 0.114s, compared to 8.566 seconds for OpenAI's GPT-5.6 Terra" and the $0.042/MTok-vs-$2/MTok comparison directly from "the demo posted on the TypeSafe website" — i.e. it is independent journalism, not an independent benchmark. [InfoWorld](https://www.infoworld.com/article/4223468/typesafe-ais-new-models-work-with-machines-not-humans.html) appeared in search results but was **not fetched**, so no claim is made here about its content. | [The Register](https://www.theregister.com/ai-and-ml/2026/09/16/typesafe-ai-debuts-model-for-machines-that-plays-doom/5296711) (fetched in full) |
| Founder credential real? | Yes. Diogo Almeida is listed as author #4 of 20 on the InstructGPT paper | [arXiv:2203.02155](https://arxiv.org/abs/2203.02155), "Training language models to follow instructions with human feedback" — author list confirmed directly from the arXiv abstract page |
| Does the product actually exist (not vaporware)? | Yes — live docs site with API reference, an open-source Python adapter repo (MIT license, 80 stars, real commit history) | [docs.typesafe.ai](https://docs.typesafe.ai/) (via its own `llms.txt` index), [github.com/typesafe-ai/system-one-adapter-python](https://github.com/typesafe-ai/system-one-adapter-python) |

`docs.typesafe.ai/llms.txt` was fetched directly and used as the primary-source index: it is not
empty, and it lists ~35 real, individually-fetchable docs pages (introduction, quickstart,
`concepts/system-one`, `concepts/state`, `primitives` + `primitives/choice|score|noul`, `models`,
`api`, SDK function references, an `agent-skill` page, cookbooks, and `model-jaggedness/jev-1.13`).
It corroborates that "System One model" and "Jev" are real, actively-documented product
terms — the vendor has shipped a full docs site consistent with the blog's claims, not just a
single announcement page. It does **not** corroborate the performance numbers themselves: none of
the pages it links to (checked: `system-one`, `primitives/choice`, `models`, `model-jaggedness`)
contain an independent benchmark, third-party citation, or reproducible eval — they describe the
API contract and known limitations, which is consistent with the "self-reported, not yet
independently verified" verdict in the claims table below, not a refutation of it.

Verdict: the domain, organization, and people are real. This is a legitimate (if very fresh —
launched 2026-09-15/16, two to three days before this check) startup announcement, not a
fabricated or unverifiable source in the "doesn't exist" sense. The caution needed is about which
*claims inside* the post are independently checkable versus vendor-asserted, not about whether the
site itself is real.

## 2. Claim-by-claim check

| Claim in the blog post | Primary source checked | Status |
|---|---|---|
| Diogo Almeida "helped build the methods that made language models useful at following instructions" (i.e., InstructGPT/RLHF) | [arXiv:2203.02155](https://arxiv.org/abs/2203.02155) author list | **Confirmed** — he is a listed author. Note: RLHF as a technique predates this paper — [Christiano et al., "Deep reinforcement learning from human preferences," arXiv:1706.03741, 2017](https://arxiv.org/abs/1706.03741) — so "co-inventor of RLHF" overstates what InstructGPT authorship alone establishes. This exact inflated phrasing appears in independent press, not just secondary blogs: The Register's own article calls Almeida "one of the co-inventors of reinforcement learning for human feedback (RLHF) and ChatGPT." The blog post itself makes the narrower, accurate claim ("I helped build the methods..."). |
| "System One Model" is a new model class; Jev is the first public one | [docs.typesafe.ai/concepts/system-one](https://docs.typesafe.ai/concepts/system-one) | **Confirmed as a vendor-defined category** — this is TypeSafe's own terminology for its own product, documented consistently across the blog and docs. It is not an existing, externally-standardized model class. |
| Training method "Reinforcement Learning for Calibrated Decisions (RLCD)" | Blog post only; no dedicated docs page, paper, or repo describing the algorithm found | **No primary technical source found.** The FAQ item "Why was a new training algorithm needed?" is present as a heading in the page's static HTML with no answer text rendered (likely a JS-driven accordion) — so even TypeSafe's own page doesn't statically expose the explanation. **Also: name collision.** "RLCD" is the exact acronym for an unrelated, pre-existing method, [Yang et al., "RLCD: Reinforcement Learning from Contrast Distillation," ICLR 2024](https://arxiv.org/abs/2307.12950) (Meta/Berkeley/UCLA), with a public [reproduction repo](https://github.com/facebookresearch/RLCD). TypeSafe's post does not flag the reuse. |
| Parallel, non-autoregressive sampling architecture | [docs.typesafe.ai/introduction](https://docs.typesafe.ai/) and [primitives docs](https://docs.typesafe.ai/primitives.md) describe the request/response shape (typed `Choice`/`Score`/`Noul` questions answered against one `state` in one call) | **Consistent with docs**, but no architecture paper, weights, or technical report was found — only product-level documentation of the API contract, not the model internals. |
| "Two orders of magnitude faster and more efficient" than existing LLMs; 70ms–500ms end-to-end | Blog "Frontiers, Old and New" table and "Evidence" section | **Self-reported only.** The blog explicitly says its own published evals are "run from our laptops on the West Coast" and offers no third-party reproduction. No independent benchmark of Jev's latency was found anywhere in press or academic coverage. |
| Pricing: $0.042/MTok input, output free | [docs.typesafe.ai/models](https://docs.typesafe.ai/models) confirms the pricing *structure* ("Output tokens are free... A Btok is a billion tokens and an Mtok is a million tokens"); the exact `$0.042` figure was not extracted from that page's price table in this pass, but the same figure is independently repeated by [The Register](https://www.theregister.com/ai-and-ml/2026/09/16/typesafe-ai-debuts-model-for-machines-that-plays-doom/5296711) ("Jev charges $0.042 / MTok for input and $0 for output") | **Structure confirmed in docs; exact figure sourced from the blog and repeated (not independently re-derived) by The Register.** Still a vendor-set price for a waitlisted, early-access product — no independent party has been billed at this rate. |
| "Can't hallucinate" / 0% type errors, plotted as literal 0% | Blog "Hallucination and Type-safety" section | **Blog's own hedge, quoted directly:** *"Our number is not empirical. Schema matching is guaranteed, thus we can confidently add 0% into the plots."* What's actually true by construction is schema conformance over a closed, predefined output space (the model can't emit a value outside the declared `Choice`/`Score`/`Noul` schema) — not that its *decisions* are always correct. TypeSafe's own docs list known weaknesses: see [Jev 1.13 "jaggedness" page](https://docs.typesafe.ai/model-jaggedness/jev-1.13) ("Jev isn't perfect... jagged edges we are aware of"), which undercuts the marketing framing of "can't hallucinate" as a claim about answer quality rather than output format. |
| Wikiracing demo: "Jev supports a cardinality up to 255" | Blog + docs | **Confirmed** (addendum 2026-09-18, second pass). The [Choice primitive docs](https://docs.typesafe.ai/primitives/choice.md) page fetched in the first pass stated no limit, but `docs.typesafe.ai/llms-full.txt` ("Two limits") says a `Choice` question allows at most 255 options. See `jev-architecture-unmasked-archerhume-2026-09-18.md`. |
| External LLM-latency comparison, "3 to 329 seconds" for frontier models | Cited by the blog as [llm-benchmarks.diegoromero.es](https://llm-benchmarks.diegoromero.es/) | **Not independently confirmed.** A direct fetch of this URL returned HTTP 403 during this review, so its content, ownership, and independence from TypeSafe could not be verified — it is cited here only as "the external source the blog itself points to," not as a checked fact. |
| $40M seed funding led by DCVC | Company's own press release | **Confirmed as issued**, via [BusinessWire](https://www.businesswire.com/news/home/20260915525333/en/TypeSafe-AI-Emerges-From-Stealth-With-$40M-in-Funding-With-New-Model-for-Composable-AI) — this is a company-issued release (primary in the sense of "this is what the company claims," not an independent audit of the cap table). Independent outlets (The Register, InfoWorld) confirm the launch happened; none independently verified the funding amount or investor. |
| Named "Jev" after William Stanley Jevons (Jevons paradox) | Blog FAQ | Jevons and the Jevons paradox are real, well-documented 19th-century economics; no verification needed beyond confirming the blog's own stated etymology, which reads as-is in the fetched page. |
| Inspired by Kahneman's *Thinking, Fast and Slow* System 1/2 framing | Blog FAQ | Real book, correctly attributed; see next section for how this framing has already been used elsewhere in AI. |

## 3. Broader context: this framing isn't new, and cuts the opposite way from the recent trend

TypeSafe did not originate the "System 1 / System 2" metaphor for AI models. Yoshua Bengio used
the identical Kahneman framing in his NeurIPS 2019 keynote, "[From System 1 Deep Learning to
System 2 Deep Learning](https://slideslive.com/38922304/from-system-1-deep-learning-to-system-2-deep-learning)"
(primary recording; secondary write-up: [bdtechtalks](https://bdtechtalks.com/2019/12/23/yoshua-bengio-neurips-2019-deep-learning/))
— arguing that deep learning had already achieved System-1-like fast perception and needed to
move *toward* System 2 (deliberate reasoning, planning, compositionality). More recently,
OpenAI's [o1 reasoning models](https://openai.com/o1/) (Sep–Dec 2024), which spend extra
"thinking" compute before answering, have been **widely described by commentators** using this
same System 1/2 vocabulary as a move further toward System 2 — OpenAI's own o1 page talks about
the model "thinking before it responds" but was not confirmed in this review to invoke the
Kahneman System 1/2 terms itself, so that attribution is to commentary, not to OpenAI directly.

TypeSafe's actual novelty claim is the reverse bet: instead of pushing models toward System-2
deliberation, ship a model that deliberately drops language generation and stays System-1-shaped
(fast, structured, non-verbal) for machine-to-machine automation. That's a legitimate and
interesting positioning claim, but it's a repackaging of a five-plus-year-old metaphor for a new
product category, not a new theoretical contribution — and the post's FAQ, in the fetched static
page, only names the Kahneman/Bengio-style inspiration; it does not cite either Bengio's prior
System 1/2 usage in AI or acknowledge that "System 2" framing already dominates the field's most
recent frontier-model narrative (reasoning models).

## 4. What could not be verified independently

- Any of Jev's specific latency, cost-efficiency, or accuracy numbers against an independent,
  reproducible benchmark — none exists yet; the product is in waitlisted early access, so no
  outside party has been able to test it.
- The technical content of "Reinforcement Learning for Calibrated Decisions" (RLCD) beyond its
  name and a one-line description — no paper, technical report, or code was found describing the
  algorithm itself (as distinct from the API/product built on top of it).
- The Pareto-frontier and hallucination benchmark charts in the blog post are self-hosted images
  (`framerusercontent.com`) built from TypeSafe's own eval runs; the underlying eval data,
  prompts, or harness are not published in a form that would let a third party reproduce them.
- The blog's own external comparator, `llm-benchmarks.diegoromero.es` — a direct fetch attempt
  returned HTTP 403, so its content and independence from TypeSafe were not verifiable in this
  pass.
- ~~The "cardinality up to 255" figure for Choice questions~~ — resolved in the second pass:
  documented in `docs.typesafe.ai/llms-full.txt` ("Two limits").
- Whether InfoWorld's coverage is independent reporting or a press-release rewrite — the article
  was found via search but not fetched in this pass.

## 5. Addendum, 2026-09-18: OpenRouter listing check

Fetched [openrouter.ai/~typesafe/jev-latest](https://openrouter.ai/~typesafe/jev-latest) on
2026-09-18, at the coordinator's request, as a possible independent-ish data point (OpenRouter
is a third-party model marketplace/router, not TypeSafe's own site).

1. **The listing is real, not a 404 or placeholder.** It's a live OpenRouter model page: "TypeSafe:
   Jev Latest," slug `~typesafe/jev-latest`, an OpenAI-compatible quick-start snippet, and a FAQ
   block. It shows `jev-latest` as an alias that "always redirects to the latest model in the Jev
   family," currently pointing at `jev-1.13`. Per the page's own FAQ, it was "released on September
   18, 2026" — the same day as this fetch, so the listing is brand new and has had essentially no
   time to accumulate independent signal.

2. **What it shows, and how it compares to the blog's self-reported numbers:**
   - **Pricing:** "$0.042/M input tokens and $0.00/M output tokens" — matches the blog and
     `docs.typesafe.ai/models` exactly. This is **not independent corroboration of the price being
     real-world/sustainable**, only confirmation that OpenRouter's listing (which model vendors
     configure themselves) agrees with what TypeSafe states elsewhere.
   - **Context window:** 32,000 tokens — consistent with the *smaller* of the two figures
     `docs.typesafe.ai/models` gives ("the 32k budget applies to the state plus the single longest
     question"); OpenRouter doesn't surface the docs' separate 64k combined-state-plus-all-questions
     figure, so this is a partial match, not a contradiction.
   - **Throughput/latency stats:** **None found.** The fetched page has no tokens-per-second,
     latency, or uptime chart of the kind OpenRouter normally shows for high-traffic models — it
     does not corroborate or contradict the "two orders of magnitude faster" / "70–500ms" claims
     either way.
   - **Usage volume:** **None.** The page states outright, "No usage data available yet" under
     "Top models used by Jev Latest." So there's no independent adoption or call-volume signal to
     weigh against the vendor's own efficiency claims.
   - **Provider routing:** No list of independent backing providers was found in the fetched
     content (unlike multi-provider OpenRouter listings for open-weight models); consistent with
     Jev being served solely by TypeSafe's own endpoint (`api.typesafe.ai/v1/systemone`), not routed
     across third-party infrastructure.

3. **Reviews/ratings:** **None present.** No user reviews, star ratings, or comments section was
   found on the fetched page or in a targeted follow-up search of the indexed content.

**Net effect on the verdict:** the OpenRouter listing corroborates that Jev is a real, live,
callable model (matching pricing and context-window figures already sourced from TypeSafe's own
docs) but adds **no independent data** on the speed, efficiency, or adoption claims — it's a
same-day, zero-usage listing with no throughput data and no reviews. It doesn't move any claim in
the table above from "self-reported" to "independently verified."

## Addendum, 2026-09-18: applicability to matt-harness

Checked whether Jev's core mechanism — closed-schema, non-generative output that structurally
can't emit outside a declared type — has anything to offer this repo. It does not need to be
adopted from Jev: mh already has the equivalent via `codex exec --output-schema` (two JSON
Schemas, `skills/review/deep-audit/references/checker-output-schema.json` and
`skills/workflow/idea-audit/references/attacker-output-schema.json`), shipped weeks before this
research. The actual gap found was narrower and unrelated to Jev specifically, and not universal:
`--output-schema` is a Codex CLI flag with no Claude Agent-tool equivalent, so a Claude fallback
path *could* ship both unenforced and under-instructed — but not every one did. Idea-audit's
Claude fallback already carried an explicit output-shape contract
(`skills/workflow/idea-audit/references/attacker-brief.md`'s `## Output` section, wired into its
`general-purpose` fallback dispatch). The two paths that were genuinely under-instructed were
`docs/reference/spawn-brief.md`'s dispatched-validator template (the return contract lived outside
the fenced brief) and `skills/review/deep-audit/SKILL.md`'s fallback acceptance criterion (written
purely in Codex-CLI terms, unsatisfiable on the Claude path) — both fixed same date. Also confirmed
against code.claude.com/docs that Claude Code has no producer-side enforcement mechanism to adopt
even if desired: `SubagentStop` is observation-only, there's no output-schema frontmatter field
for agents, and plugins cannot define native tools. `compliance-audit`'s own Claude fallback was
checked separately and found not to depend on any Codex-only artifact in the first place (no
`spawn-brief`/`output-schema`/`output-last-message` reference in its SKILL.md), so there was no
comparable gap to defer there.

## Addendum, 2026-09-18: `concepts/use-case-map.md` drill-down

Fetched [docs.typesafe.ai/concepts/use-case-map.md](https://docs.typesafe.ai/concepts/use-case-map.md)
at the coordinator's request. **The page exists** (200 OK, ~11.4KB, not a 404 or stub).

**1. What it actually is.** Despite the name, this is **not a fourth API primitive or a
"concept" with its own request/response shape** the way `Choice`, `Score`, and `Noul` are (see
Section on primitives above). It's a business-facing brainstorming index titled "Example use
cases": "Use this map to brainstorm where TypeSafe could fit in your industry. Open the closest
industry, scan the example decisions, and adapt them to the documents and actions in your own
workflow." It has three parts:
  - Five "Example use case categories" cards — *AI Automation Software*, *Real-time applications*,
    *AI Map Reduce over Big Data*, *Universal Verification*, *Harness Engineering* — each a short
    positioning paragraph, not a technical spec.
  - An accordion of "Example automation use cases" by vertical: at minimum *Search and retrieval*,
    *Scientific discovery*, *Model routing*, *Moderation and trust and safety*, *Customer support*,
    *Demand forecasting*, *Legal and compliance*, *Insurance claims*, *Risk assessment*, and
    *Graphs and knowledge graphs* were retrieved (each 4–5 bullet points of example decisions);
    the page's own heading ("Example task categories") implies more than were captured by this
    pass's targeted searches, so this list should be read as a confirmed subset, not necessarily
    exhaustive.
  - A "Decision shape" reference table with columns *Decision shape / Reach for it when /
    Examples*, covering: Classification, Detection, Scoring, Routing, Search, Retrieval, Ranking,
    Verification, ML Feature Extraction, and Structured Data Extraction.

  **Relation to Choice/Score/Noul and `state`:** the page never states an explicit mapping from
  its ten "decision shapes" to the three underlying primitives — there is no "built with: Choice"
  column. The mapping is left implicit/inferable (e.g., *Detection*, defined as "a probability
  that one property is present," reads as a `Noul` question; *Classification*/*Routing*, "one
  known category should win," reads as `Choice`; *Scoring* reads directly as `Score`). Shapes like
  *Search*, *Retrieval*, *Ranking*, *Verification*, and *Structured Data Extraction* have no
  stated primitive at all in the fetched content — presumably composed from repeated or parallel
  Choice/Score/Noul calls against a `state`, per the general primitives docs, but this page does
  not spell that composition out.

**2. Concrete examples/snippets.** **None.** Unlike `primitives/choice.md` (which has a full
JSON request/response example), this page is pure prose bullet lists per industry — no code,
no JSON, no worked request/response scenario anywhere in the fetched content.

**3. New claims checked against primary sources:**
  - *"Real-time speeds (150ms)"* (Real-time applications card) — a new specific number not seen
    in the blog's own "70ms–500ms" range table, but within it. Self-reported, no independent
    benchmark found for this figure specifically, consistent with every other latency figure in
    this file.
  - *"100x cheaper"* (AI Map Reduce over Big Data card) — restates the cost-efficiency framing
    already in Section 2's claims table ($0.042 vs. $0.20–$10/MTok); not a new, separately-sourced
    number, just a rounder marketing figure for the same underlying comparison.
  - *"run it a million times in the background without a human co-pilot"* (AI Automation Software
    card) — qualitative marketing language, not a checkable quantitative claim.
  - *"Universal Verification"* — pitches Jev as a detector of *other* AIs' failures: "Detect
    jailbreaks, citation errors, hallucinations, mistakes, or other error-modes that other AIs or
    LLMs make at a fraction of the cost for the actual LLM call." This is a new positioning claim
    not previously in this file, and it does not have an independent benchmark either — no
    accuracy figures for Jev-as-verifier were found on this page or elsewhere in this review.

**4. Does this page nuance the open RLCD/"0% hallucination" question?** **No — it adds nothing
mechanistic.** This page is a use-case/marketing index, not architecture or training
documentation; it contains zero explanation of how RLCD works or how the closed-schema guarantee
is implemented. The RLCD-mechanism gap flagged in Section 2/4 above stands unchanged.

It does surface one new **internal tension worth flagging**: the "Universal Verification"
pitch asks customers to trust Jev's own judgment (a `Score`/`Noul`/`Choice` call) to catch *other*
models' hallucinations — that's a claim about decision *accuracy*, not about output-schema
conformance. But this file's Section 2 already established that Jev's own "can't hallucinate" /
"0%" figure is explicitly schema-conformance-only, by the blog's own admission ("Our number is not
empirical. Schema matching is guaranteed"), and TypeSafe's own [Jev 1.13 jaggedness
page](https://docs.typesafe.ai/model-jaggedness/jev-1.13) discloses known accuracy weaknesses. So
the use-case-map's "verify hallucinations in other AIs" pitch rests on a *judgment-accuracy*
guarantee that is a stronger, different, and — per this review — still-unverified claim, distinct
from (and not covered by) the "0% type errors" figure the blog treats as its headline evidence.

## Addendum, 2026-09-18: independent field-test evidence on the speed claim (idea-audit re-run)

Coordinator re-ran this same source through `mh:idea-audit` (2 isolated analysts + 1 adversarial
attacker, Codex primary rate-limited, Claude fallback used). Verdict unchanged from above and from
the applicability addendum: mh already has the functional equivalent, no Jev adoption warranted.
One genuinely new data point surfaced, not in the sections above:

- **Real-world reproduction found, and it's much lower than the headline number.** A UK events
  company ("Near Here") ran ~50 live moderation decisions through Jev and measured "roughly five
  times faster" than their prior LLM setup — not the blog's "up to 193 times faster than Claude
  Sonnet 5." A separate public reproduction attempt, `github.com/themsquared/jev-benchmark`,
  explicitly states it ran "no frontier-LLM baseline in these numbers... nothing here supports or
  refutes the vendor's speed and cost multipliers" — i.e. even the closest thing to an independent
  benchmark declines to validate the multiplier.
- **The vendor's own headline number is internally inconsistent.** The Register's quoted demo
  figures (0.114s vs. 8.566s, already cited above) work out to `8.566 / 0.114 ≈ 75x`
  (verified: `python3 -c "print(8.566/0.114)"` → `75.14`) — not the "193.6x" the launch page's own
  chart headlines. Both numbers come from TypeSafe's own materials; they don't agree with each
  other.

Net effect: strengthens, doesn't change, the existing "self-reported only, no independent
reproduction" finding — now there IS an independent reproduction, and it lands roughly an order of
magnitude below the vendor's claim, with the vendor's own page also disagreeing with itself on the
multiplier.

## Sources

- [TypeSafe AI blog post (subject of this review)](https://typesafe.ai/blog/introducing-system-one-models-and-jev)
- [docs.typesafe.ai](https://docs.typesafe.ai/) — introduction, `/concepts/system-one`, `/primitives`, `/primitives/choice`, `/models`, `/model-jaggedness/jev-1.13`, `/llms.txt`
- [github.com/typesafe-ai/system-one-adapter-python](https://github.com/typesafe-ai/system-one-adapter-python)
- [arXiv:2203.02155 — Training language models to follow instructions with human feedback (InstructGPT)](https://arxiv.org/abs/2203.02155)
- [arXiv:2307.12950 — RLCD: Reinforcement Learning from Contrast Distillation (unrelated, name-colliding prior work, ICLR 2024)](https://arxiv.org/abs/2307.12950)
- [BusinessWire — TypeSafe AI funding announcement](https://www.businesswire.com/news/home/20260915525333/en/TypeSafe-AI-Emerges-From-Stealth-With-$40M-in-Funding-With-New-Model-for-Composable-AI)
- [The Register — TypeSafe AI debuts model for machines that plays Doom](https://www.theregister.com/ai-and-ml/2026/09/16/typesafe-ai-debuts-model-for-machines-that-plays-doom/5296711)
- [InfoWorld — TypeSafe AI's new models work with machines, not humans](https://www.infoworld.com/article/4223468/typesafe-ais-new-models-work-with-machines-not-humans.html) (found via search, **not fetched**)
- [SlidesLive — Bengio, "From System 1 Deep Learning to System 2 Deep Learning," NeurIPS 2019](https://slideslive.com/38922304/from-system-1-deep-learning-to-system-2-deep-learning) (primary); [bdtechtalks write-up](https://bdtechtalks.com/2019/12/23/yoshua-bengio-neurips-2019-deep-learning/) (secondary)
- [OpenAI — Introducing OpenAI o1](https://openai.com/o1/)
- [arXiv:1706.03741 — Christiano et al., Deep reinforcement learning from human preferences (2017, pre-dates InstructGPT/RLHF-for-LLMs)](https://arxiv.org/abs/1706.03741)
- [llm-benchmarks.diegoromero.es](https://llm-benchmarks.diegoromero.es/) — cited by the blog as its external latency comparator; **fetch attempt returned HTTP 403, not independently verified in this review**
- [OpenRouter — TypeSafe: Jev Latest](https://openrouter.ai/~typesafe/jev-latest) (fetched 2026-09-18; see Section 5 addendum)
- [docs.typesafe.ai/concepts/use-case-map.md](https://docs.typesafe.ai/concepts/use-case-map.md) (fetched 2026-09-18; see use-case-map addendum)

## Additional real-world use case survey — 2026-09-19

Scope: adopters beyond the four already on record (LangChain `ModelRouterMiddleware`, Browser Use's
`jev-ultrafast`, TypeSafe's own Agent Skills repo, Near Here's ~5x field test vs. the vendor's
193x claim, `themsquared/jev-benchmark`'s no-baseline repro). Method: `gh search code` for real
package-manifest dependencies on TypeSafe's SDK packages (not mentions), `gh api` to confirm each
repo isn't a fork/spoof, WebSearch/WebFetch for independent write-ups, one HN thread, and
`qmd query` against `llm-wiki` run this pass (`TypeSafe AI Jev System One models adoption` —
top hit 0.75, an unrelated agentic-engineering skill doc; nothing TypeSafe/Jev-specific indexed).

### A second, independently-adopted SDK package

`jev-somkiat-blog-audit-2026-09-18.md` row 1 already confirmed `@typesafe-ai/sdk` (TypeSafe's own
direct JS SDK) as real. This pass found the ecosystem's larger adoption vector is a **different,
second package**:
[`@ai-sdk/typesafe-ai`](https://www.npmjs.com/package/@ai-sdk/typesafe-ai), Vercel's own official
provider for TypeSafe inside the **Vercel AI SDK monorepo** (`vercel/ai`, 26,842 stars, confirmed
via `gh api repos/vercel/ai` — not a fork). `packages/typesafe-ai/package.json` in that repo is at
version `3.0.4`, Apache-2.0. This is the single most significant new fact of this pass: Vercel
shipping and versioning a first-party `@ai-sdk/typesafe-ai` provider is a materially stronger
adoption signal than any single downstream app, because every project below reaches Jev through it.

### New independent adopters found (real `package.json` dependency, confirmed non-fork via `gh api`)

| Repo | Stars | Task Jev/`@ai-sdk/typesafe-ai` performs | Independence |
|---|---|---|---|
| [`coldteadotai/abide`](https://github.com/coldteadotai/abide) | 105 | **Verification** — judges every AI-coding-agent edit/turn against a repo's own `AGENTS.md` rules, one typed yes/no question per rule, blocks/fixes in-session | Third-party product (`npx @coldtea/abide`), no disclosed TypeSafe relationship |
| [`noelzappy/tripwire`](https://github.com/noelzappy/tripwire) | 2 | **Verification/guardrail** (designed for) — judges LLM responses on 7 checks (PII leak, prompt-injection compliance, hallucination risk, etc.) via one Jev call | Independent OSS, npm-published, CI badge; explicitly not vendor content — **but pre-production**: README states v0.1, "No accuracy numbers against real Jev yet... Do not put this in front of users." Tests run against a mock judge, not real Jev. Not a shipped use. |
| [`dakdevs/decide-mcp`](https://github.com/dakdevs/decide-mcp) | 0 | **Routing/scoring** — configurable decision MCP server, percentage scores + bias-profile routing | Independent, early-stage |
| [`rszhd/signalscout`](https://github.com/rszhd/signalscout) | 8 | **Classification** — finds public conversations describing a problem a product solves | Independent |
| [`jarrodwatts/jev-trader`](https://github.com/jarrodwatts/jev-trader) | 1,011 | **Decision/ranking** — buy/sell call every ~300ms Monad block on a live Kuru MON-USDC order book, real on-chain limit orders | Jarrod Watts: ex-Thirdweb/Polygon Labs DevRel (2022–2024, confirmed via GitHub profile + web search), currently DevRel at Cube Labs — no TypeSafe affiliation found; real trading, real money |
| [`jkudish/jev-browser`](https://github.com/jkudish/jev-browser) | 123 | **Routing/extraction** — browser-agent action selection (operation + element), separate from `browser-use/jev-ultrafast` already on record | Independent developer repo |

`gh search code` (package-manifest dependency search) is the source for the six rows above.
Separately, plain **WebSearch** (not code search, not opened/inspected) surfaced more
"jev-trader"-named repos (`aowang-ai/jev-trade` — targets Hyperliquid, not Kuru, so not obviously a
copy of `jarrodwatts/jev-trader`; `zadescoxp/Jev-Trades`; `rnjsxodyd90/jev-trading-bot-derived-backup`)
and "awesome-jev" list repos (`AnotiaWang`, `yibie`, `valentynkit`) — none of these were inspected,
so they're noted as surfaced, not counted as verified adopters. `genesiscz/GenesisTools` (7 stars)
also matched the `gh search code` dependency search but its README doesn't mention TypeSafe/Jev
anywhere (checked); dropped from the table for lack of a verifiable use case.

### `coldteadotai/abide` — most interesting case, self-reported accuracy gap included

Abide's own README ships a measured, methodologically transparent number that **cuts against** the
vendor's accuracy framing rather than repeating it: replaying 93 real Claude Code sessions (1,256
edits, 147 turns, cost 22 cents) against each repo's own `AGENTS.md`, "Jev flagged 39 edits and 15
turns; an independent reviewer confirmed 10 and 11." That is roughly **26% precision at the
edit level, 73% at the turn level** — the author reports this as-is rather than rounding it up, and
links the full per-rule table (`benchmarks/replay/README.md`, not fetched in this pass). This is a
real third party shipping a real verification task on Jev, with an honestly-reported miss rate — a
more useful and more independent data point than any vendor benchmark, because it's a builder
reporting against their own product's interest, not TypeSafe's.

### Independent benchmark with disclosed non-affiliation and mixed results

[Robin Lorenz / PrimeLine, "TypeSafe Jev vs Claude Code: 4 Models, 2 Real Jobs"](https://primeline.cc/blog/typesafe-jev-pre-registered-test)
— no disclosed TypeSafe relationship; author states the test corpus (798 commit messages, 450
knowledge-base notes) comes from their own machine and is "substantially Claude-influenced text,"
so results aren't a clean third-party corpus either. Measured: Jev 65.7% vs. Claude Haiku 4.5
54.8% on commit-message classification; Haiku 97.8% vs. Jev 90.7% on knowledge-category
classification — i.e. Jev wins one task, loses the other, not a uniform win. Cost claim
($0.042/M input tokens vs. Haiku's ~$1/M) repeats the vendor's own pricing figure, not an
independent cost measurement. Partial reproducibility: methodology described in prose, a linked
repo (`primeline-ai/evolving-lite`) exists but the specific benchmark data/code weren't confirmed
present in this pass.

### Independent developer deep-dive, no production use yet

[Flavio Copes, "A deep dive into Jev, TypeSafe's System One model"](https://flaviocopes.com/jev/)
— independent blogger, no disclosed TypeSafe relationship. Explicitly states "I have console
access, but I haven't put Jev into production yet" and labels his own numbers (1,018 papers
classified for $0.08, 98,000 listing classifications in 10 minutes, 11/11 on an invoice test) as
"early experiments, not production case studies." Counts as an honest non-adopter data point, not
a production use case — included because it's the kind of skeptical-but-fair independent source
the task asked to capture.

### Independent reproduction attempt, negative on capability (not just speed)

[HN: "Jev: The Model That Gives AI the Properties of Code"](https://news.ycombinator.com/item?id=49716682)
and the follow-up [HN: "Reverse-engineered Jev-like model"](https://news.ycombinator.com/item?id=49731282)
(citing an independent open-source recreation, not an official TypeSafe repo). Top critical
comments in the second thread: a demo's "left and right panels almost never agree on anything"
(accuracy-vs-speed skepticism), and a small reverse-engineered model "couldn't reliably solve
basic mazes" — "Jev is not interesting if it's not 'smart,' a 1B param model is most definitely not
smart." This is independent, unsponsored, and negative — a valid finding under the task's own
"negative or mixed results count" instruction, distinct from the Near Here/`jev-benchmark` speed
finding already on record.

### Verdict of this pass

Beyond the four adopters already documented, this pass adds: **one platform-level adoption**
(Vercel AI SDK's official `@ai-sdk/typesafe-ai` provider package, the real distribution channel for
most of what follows), **five small independent downstream projects** genuinely depending on it in
their manifests (abide, decide-mcp, signalscout, jev-trader, jev-browser — trading and
coding-agent-verification are the two production-shaped, actually-running-against-real-Jev tasks
among them; tripwire is a sixth manifest dependency but is pre-production, not a shipped use),
**one self-reported but methodologically transparent accuracy gap** from a real adopter (abide,
26%/73% precision), **one mixed-result independent benchmark** with disclosed non-affiliation
(PrimeLine), and **one independent, unsponsored, negative capability finding** (HN
reverse-engineering thread). No case found here is TypeSafe's own marketing reissued as a "case
study" via a partner blog — the closest to that risk (PrimeLine, madewithjev.com) both showed
independent authorship on inspection (madewithjev.com's footer: "Curated by @kraayenjon," a third
party, not typesafe.ai). Ryan Vogel's email-triage number ("1,700 emails for 18 cents") surfaced
repeatedly in secondary sources (search-engine summaries, other write-ups) but no primary post by
Vogel was fetched in this pass — noted, not counted as a verified case. This does not reopen or
change mh's own adoption verdict, which stays out of scope for this survey.

### Additional sources (this pass)

- [npmjs.com/package/@ai-sdk/typesafe-ai](https://www.npmjs.com/package/@ai-sdk/typesafe-ai)
- [github.com/vercel/ai](https://github.com/vercel/ai) — `packages/typesafe-ai/package.json`
- [github.com/coldteadotai/abide](https://github.com/coldteadotai/abide)
- [github.com/noelzappy/tripwire](https://github.com/noelzappy/tripwire)
- [github.com/dakdevs/decide-mcp](https://github.com/dakdevs/decide-mcp)
- [github.com/rszhd/signalscout](https://github.com/rszhd/signalscout)
- [github.com/genesiscz/GenesisTools](https://github.com/genesiscz/GenesisTools)
- [github.com/jarrodwatts/jev-trader](https://github.com/jarrodwatts/jev-trader)
- [github.com/jkudish/jev-browser](https://github.com/jkudish/jev-browser)
- [madewithjev.com](https://madewithjev.com/) — third-party-curated showcase, not typesafe.ai
- [primeline.cc/blog/typesafe-jev-pre-registered-test](https://primeline.cc/blog/typesafe-jev-pre-registered-test)
- [flaviocopes.com/jev](https://flaviocopes.com/jev/)
- [news.ycombinator.com/item?id=49716682](https://news.ycombinator.com/item?id=49716682)
- [news.ycombinator.com/item?id=49731282](https://news.ycombinator.com/item?id=49731282)
