# "Jev's Architecture Unmasked" (Archer Hume) — source and claims check

Date: 2026-09-18. Method: fetched the essay
(`archerhume.com/posts/jevs-architecture-unmasked/`, dated 2026-09-17) and every self-published
evidence file it links under `archerhume.com/research/jev/*.json` (11 files, all HTTP 200),
then checked each claim against the source that owns it: TypeSafe's docs
(`docs.typesafe.ai/llms-full.txt`, the API reference, the ML primer), the launch blog, the
pinned revision `fb52b103` of `typesafe-ai/system-one-adapter-python`, the six arXiv papers
cited, the author's own `/about` page, and the Hugging Face "Jev Reproductions Tracker" space.
Where the essay reports a number derived from its own bundle (ECE, log-odds shift, MMLU-Pro),
that number was recomputed from the JSON rather than trusted. `qmd` (llm-wiki, mh-research)
had no prior coverage beyond the sibling note below. X/Twitter posts could not be fetched.

Companion note (vendor launch post, same day): `typesafe-ai-system-one-jev-2026-09-18.md`.
This note does not repeat that ground; it records where the essay agrees, contradicts, or
adds.

## TL;DR

- **Independent author, with a declared stake.** Archer Hume is a Melbourne engineer,
  co-founder of Doccy/Medlo (telehealth), no stated TypeSafe affiliation, one early-access
  account. But the HF reproductions tracker lists "Archer Hume's promised open-weight version"
  of Jev, announced alongside this essay. He is a third party to TypeSafe, not a disinterested one.
- **The essay is honest about what it is: a black-box reconstruction.** It labels its own
  claims as published / observed / inferred and says "this is clearly all quite speculative."
  Its evidence bundle is real, downloadable, and internally consistent: ECE 0.0313 on 1,200 MMLU
  items, the +0.38 to +0.11 log-odds shift, and the 84.6% MMLU-Pro figure all recompute exactly
  from the JSON. That is a reproduction of the author's arithmetic, **not** an independent
  observation of Jev; every probe is one account, one region, one day, one model version.
- **Strongest independently checkable finding: the `confidence` field is arithmetic, not a
  learned estimate.** The adapter formula `(p_max - 1/K)/(1 - 1/K)` reproduces every worked
  example in TypeSafe's own API docs (0.88, 0.39, 0.53, 0.16, 1.0) within the docs'
  two-decimal rounding. Anyone thresholding on
  `confidence` is thresholding on a rescaled max-probability.
- **Two things the essay presents as facts are undocumented:** the 32,768/65,536 token limits
  (his own probe metadata says the docs state no limit) and "TypeSafe refuses to share their
  research" (an absence of a paper, not a stated refusal). The MoE backbone and causal decoder
  are explicitly author inference.
- **Correction to the companion note:** the 255-option cap *is* documented
  (`llms-full.txt`: "A `Choice` question allows at most 255 options"). The prior note marked it
  "uncorroborated in docs." See §7 NEEDS-DECISION.
- **Adoption decision unchanged (declined).** Nothing here gives mh a new reason to adopt; the
  order-sensitivity result (0.84–0.89 → 0.93–0.96 on label reversal) and the arithmetic
  confidence field both argue for keeping the schema-constrained equivalent mh already has.

## 1. Who wrote it, and what relation to TypeSafe

| Claim | Source checked | Verdict |
|---|---|---|
| Author is Archer Hume | `<meta name="author" content="Archer Hume">` on the post; `/about` page | **Confirmed.** |
| Independent of TypeSafe | `/about`: co-founder Doccy & Medlo (May 2026–), founding engineer there (Oct 2025–May 2026), app dev at Gradient Information Systems (2023–25), Melbourne. No TypeSafe, DCVC, or OpenAI link anywhere on the page. Essay Methods: "one early-access account and one observed service region." | **Confirmed as stated; no contrary evidence.** He is a customer-tier outsider, not staff or investor. |
| Has a stake in the topic | HF space `multimodalart/jev-reproductions-tracker`, `index.html`: `"Archer Hume's promised open-weight version. Announced with the architecture post; training 'takes time'"`, linking `x.com/4rcherhume/status/2100555442061820286` | **Confirmed.** He has publicly promised his own open-weight Jev. The essay does not mention this. Treat the reconstruction as also being a design brief for that project. |
| "10,000 API calls" (subtitle) | Methods section counts: 1,029 + 6,800 + 146 + 311 + 445 + 192 + 148 + 181 + 105 + 35 = 9,392 | **Approximately right.** Rounded up in the headline; the body's own counts sum to ~9.4k. |
| Opening quote: Niels Rogge, "12 million views for a JSON classifier?" | `x.com/NielsRogge/status/2100114968460820986` | **Unverified.** X is not fetchable from this environment. |
| "scouring ... with Astra" | Essay text only | Author's tooling note (presumably the Codex "Astra" model tier; the essay does not say). Not a claim about Jev. |

## 2. Claims sourced to TypeSafe (published evidence)

| Essay claim | Primary source | Verdict |
|---|---|---|
| Launch says "Jev outputs all probabilities in parallel instead of autoregressively generating by token" | `typesafe.ai/blog/introducing-system-one-models-and-jev`, "Side-by-side demonstration" | **Confirmed, verbatim.** |
| Launch says RLCD optimises for "answers with epistemically honest probabilities on System One tasks" | Same blog, comparison table row "Calibrated decisions" | **Confirmed, verbatim.** |
| Primer presents RLCD as a post-training path from pretrained language models | `docs.typesafe.ai/introduction/machine-learning-primer`: RLCD card "trains TypeSafe to return decisions and calibrated probabilities instead of generated text"; figure alt-text "Pretrained language models branch into muted RLHF and RLVR paths and an emphasized RLCD decision-model path" | **Confirmed.** The "post-training from a pretrained LM" reading rests on the figure caption and the RLHF/RLVR/RLCD side-by-side, not on explicit prose. Fair reading, thin source. |
| Question ID "is not sent to the underlying model and is not used in inference" | `llms-full.txt`, API reference `questions` map entries; also the Tip "Question IDs are for your code. They are not sent to the model." | **Confirmed, verbatim.** |
| API accepts at most 255 options | `llms-full.txt`: "A `Choice` question allows at most 255 options. With more candidates than that, narrow in two stages" | **Confirmed in docs.** (Contradicts the companion note's "uncorroborated" line — see §7.) Essay's added claim that the cap "is enforced by request validation, not the model" is author inference. |
| `confidence` for Choice = `(p_max - 1/K)/(1 - 1/K)`, 1.0 when K=1; Score uses distance from the modal level | `raw.githubusercontent.com/.../fb52b1030b7fc1f4f1cf39910afa5da54f9835e3/src/system_one_adapter/_utils/confidence_metrics.py`: `choice_confidence` returns `(max(normalized_probs) - uniform_probability) / (1.0 - uniform_probability)`, early-returns `1.0` for `len(probs) == 1`; `score_confidence` computes `distance_from_mode` vs uniform MAD | **Confirmed in code.** Caveat the essay under-states: that repo is a "Drop-in TypeSafeClient replacement backed by LLM APIs" (repo About), an emulation layer, not Jev's server. **However**, the formula reproduces every worked example in TypeSafe's own API docs: `{0.08, 0.92, 0.0}` → 0.88 (docs: 0.88); K=3 → 0.40 (docs: 0.39); K=5 → 0.537 (docs: 0.53); K=4 → 0.16 (docs: 0.16); saturated cases → 1.0. So the server field is consistent with the same arithmetic. Docs describe it only as "How certain the model is, derived from probabilities." |
| Docs report an `output_tokens` usage field | `llms-full.txt` example responses (`"output_tokens": 212`, `48`) | **Confirmed.** The essay's argument that it is a billing figure computed after inference is author inference from his token-accounting probes (see §3). |
| "TypeSafe refuses to share their research" | Blog and docs: no paper, technical report, or "open weight" string anywhere (`paper` appears 3x in `llms-full.txt`, all in use-case copy) | **Author characterisation.** Consistent with the companion note (no RLCD paper exists), but no refusal is on record; it is an absence. |
| Jev enforces per-branch ~32,768 and per-request ~65,536 token limits | `llms-full.txt`: zero hits for `32768`, `32,768`, `65536`, `65,536`. His own `context-limit.json` meta: `"docs_check": "docs.typesafe.ai/llms-full.txt (2026-09-17): no stated context/token limit"` | **Author-observed, undocumented.** From 35 boundary probes. The essay's phrasing "Jev enforces two limits" reads as documented fact; it is not. |

## 3. Claims sourced to the author's own probes (observed evidence)

All of these are one account, one region, `jev-1.13.0`, 2026-09-17, server time from
`x-envoy-upstream-service-time`. "Recomputed" below means the number was re-derived from the
published JSON, which checks the author's arithmetic, not Jev.

| Essay claim | Bundle file | Verdict |
|---|---|---|
| MMLU 1,200-item ten-bin ECE = 0.0313; 990 items in the 0.9–1.0 bin | `calibration.json` (`n: 1200`, `ece: 0.031325`, `source: bench_results.jsonl`) | **Recomputed exactly**: ECE 0.0313, bins `[0,0,0,6,18,28,39,46,73,990]`, overall accuracy 91.75%. Sample source is the author's own `bench_results.jsonl`, not published beyond the sha256 in `evidence.json`. |
| "84.6% on MMLU-Pro" | `evidence.json` → `benchmarks`: `{"name": "mmlu_pro", "n": 800, "accuracy": 0.84625}` | **Recomputed from bundle; not a TypeSafe number.** Zero hits for `MMLU` in the launch blog or docs. It is the author's own 800-item run. The essay cites its own [15], so the attribution is honest, but readers should not take it as vendor-reported. |
| Adding an irrelevant fifth option shifts log-odds customer/unknown from +0.38 to +0.11; mean change −0.28, all ten blocks negative, 95% interval −0.36 to −0.19 | `followup-summary.json` `odds` + `pairedEffects` | **Recomputed**: base4 0.432 and null4 0.332 pool to 0.382; append5 0.097 and null5 0.113 pool to 0.105; difference −0.277. Unpooled append5-vs-base4 = −0.335 (SE 0.077), all 10 blocks negative. Consistent. Sound within its design (one scenario, 50 requests). |
| Question-isolation probe: secret in sibling question → p=0.00; in state → 0.90–0.92; five repeats | `evidence.json` → `questionIsolation` (`pCode: [0.0 ×5]` for with_secret; 5 per condition) | **Consistent with bundle.** The author's own caveat is recorded there too: "Learned instruction boundaries can mimic hard attention isolation." |
| Latency: ~30k tokens in ~160 ms; 1,500 questions in a few hundred ms; 192 requests, 8 reps | `latency-rerun.json` (`reps: 8`, `concurrency: 1`, 192 trials; 8 state sizes × 16 question counts) | **Consistent with bundle.** Medians in the essay match the per-size tables. Server-side header only; no hardware benchmark, load uncontrolled. |
| Tokenizer matches none of 192 public tokenizers; "445 tokenizer-fingerprint requests" (Methods) / "415 probes" (body) | `tokenizer-fingerprint.json`: 421 trials | **Minor count discrepancy.** 445 (Methods) vs 421 (file) vs 415 (body). Not a contradiction of the finding, but the numbers do not reconcile. Which 192 tokenizers were compared is not listed in the JSON meta. |
| Reference-card experiment: 12/16, 11/16, 16/16, 48/48 by card position | `followup-summary.json` `relational` (accuracy 0.75/0.75 for card-first orders, etc., n=8 each) | **Consistent with bundle.** |
| Option order flips a classification from 0.84–0.89 to 0.93–0.96 | `evidence.json` → `optionOrder` | **Consistent with bundle** (not recomputed line by line). This is the finding most relevant to anyone routing on Jev probabilities. |
| Repeated identical requests give small probability differences; key order varies | `evidence.json` → `noise` | **Consistent with bundle.** |

## 4. Architectural inferences (author speculation, labelled as such)

| Inference | Essay's own label | Note |
|---|---|---|
| Direct probability readout (prediction head, no decode loop) | "publicly described" + observed | Best-supported: rests on TypeSafe's own "outputs all probabilities in parallel" statement plus the output_tokens accounting probes. Still not a look inside the model. |
| Shared-state prefix KV cache + isolated question suffixes | observed behaviour, mechanism inferred | Hydragen (arXiv:2402.05099, Juravsky et al.) and DeFT (arXiv:2404.00242, Yao et al.) are cited as prior art, and the essay says so: "They are prior art, not evidence that TypeSafe uses either library." Both papers exist with those titles/authors. |
| Causal decoder backbone | "I assume ... for good reason" | Explicitly cannot distinguish from a bidirectional encoder. |
| Listwise option interaction; final-position head vs pointer scorer | observed (IIA shift), mechanism inferred | FIRST (arXiv:2406.15657, Reddy et al.) cited as an analogous method; exists as cited. "Neither result is decisive." |
| Training via proper scoring rule (log loss / Brier) | "My proposed training recipe" | Gneiting & Raftery 2007 and Guo et al. (arXiv:1706.04599) are correctly cited background; the essay states it "does not establish which loss TypeSafe uses, whether its pipeline is reinforcement learning in a narrow algorithmic sense." |
| Sparse MoE backbone | "least certain part"; "remains an inference, not a measurement" | Shazeer et al. (arXiv:1701.06538) exists as cited. The dense-70B-vs-10B-active timing argument depends on unknown hardware. |
| Not diffusion | author argument | "None of this requires diffusion"; consistent with docs (zero hits for `diffusion`). Note the HF tracker lists "Diffusion" as a separate reproduction category, so some third parties are betting the other way. |

## 5. Relation to the companion note

- **Agrees:** no RLCD paper/spec exists; performance figures in the launch are vendor-only; the
  "can't hallucinate" framing is about schema conformance, not decision correctness (the essay's
  own line: "Either can be miscalibrated. Neither becomes trustworthy solely because of its format").
- **Adds:** the first outsider-run calibration data (ECE 0.031 on MMLU, one region, one day); the
  IIA/option-order sensitivity results; the confidence-field formula; the undocumented token limits;
  a concrete architectural hypothesis with its uncertainty tiers spelled out.
- **Contradicts:** the companion note's row "Wikiracing demo: 'Jev supports a cardinality up to
  255' — uncorroborated in docs." The docs do state the cap (quote in §2). The companion note's
  fetch of `docs.typesafe.ai/primitives/choice.md` missed it; `llms-full.txt` has it under
  "Two limits."
- **Does not address:** the RLCD acronym collision with Yang et al. (ICLR 2024); the Bengio
  System-1/2 prior art. The essay does not use "System One" framing at all beyond quoting the launch.

## 6. Relevance to mh's prior adoption decision

Declined stands. The essay strengthens two reasons to keep the schema-constrained equivalent:
(a) `confidence` is a deterministic rescale of max-probability, so any "route on confidence"
design is really "route on p_max" with a K-dependent offset; (b) label order alone moves a
probability across a 0.9 threshold. Neither is a vendor-published caveat. Nothing here is
adoptable by mh: the essay is an analysis, not a tool, and its open-weight promise is
unreleased.

## 7. NEEDS-DECISION

1. Amend the companion note `typesafe-ai-system-one-jev-2026-09-18.md`, row "Wikiracing demo:
   'Jev supports a cardinality up to 255'", from "Uncorroborated in docs" to confirmed. Source:
   `docs.typesafe.ai/llms-full.txt`, section "Two limits": "A `Choice` question allows at most
   255 options. With more candidates than that, narrow in two stages." This note did not edit
   that file.
2. Whether to browser-fetch the two X posts left "unverified" here (the Niels Rogge quote; Hume's
   open-weight promise). Both are colour, not load-bearing; default is to leave them as-is.

## Sources

- Essay: https://archerhume.com/posts/jevs-architecture-unmasked/ (dated 2026-09-17, fetched 2026-09-18)
- Author page: https://archerhume.com/about
- Evidence bundle (all fetched 2026-09-18, HTTP 200): `https://archerhume.com/research/jev/{evidence,calibration,followup-trials,followup-summary,latency-rerun,tokenizer-fingerprint,context-limit,option-injection,output-token-accounting,option-count-latency,option-position}.json`
- TypeSafe launch blog: https://typesafe.ai/blog/introducing-system-one-models-and-jev
- TypeSafe docs (full text): https://docs.typesafe.ai/llms-full.txt ; API reference https://docs.typesafe.ai/api ; ML primer https://docs.typesafe.ai/introduction/machine-learning-primer
- Adapter repo, pinned file: https://github.com/typesafe-ai/system-one-adapter-python/blob/fb52b1030b7fc1f4f1cf39910afa5da54f9835e3/src/system_one_adapter/_utils/confidence_metrics.py
- HF tracker: https://huggingface.co/spaces/multimodalart/jev-reproductions-tracker (static space; claims read from `raw/main/index.html`, lastModified 2026-09-18T00:34Z)
- arXiv (titles verified 2026-09-18): 1706.03762 Attention Is All You Need; 2402.05099 Hydragen; 2404.00242 DeFT; 2406.15657 FIRST; 1706.04599 On Calibration of Modern Neural Networks; 1701.06538 Sparsely-Gated MoE
- Gneiting & Raftery 2007, JASA 102(477):359–378 (PDF link as cited by the essay; not re-fetched)
- Unfetchable: `x.com/NielsRogge/status/2100114968460820986`, `x.com/4rcherhume/status/2100555442061820286`
- Companion note: `docs/research/typesafe-ai-system-one-jev-2026-09-18.md`
