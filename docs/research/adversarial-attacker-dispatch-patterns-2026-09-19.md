---
lens: prior-art-survey
date: 2026-09-19
---

# Adversarial attacker/verifier/checker dispatch: how real systems build it

Date: 2026-09-19. Method: fetched primary sources directly — arXiv HTML full text (not just
abstracts) for 12 papers, first-party docs/READMEs for PyRIT, garak, AutoGen, MetaGPT, and
OpenAI's own red-teaming blog posts and whitepaper — then WebSearched only to locate those
sources, never to substitute for reading them. `qmd` against `mh-research`/`llm-wiki` surfaced two
directly relevant matt-harness research docs already on file (cited below, not re-derived).
Written as input for a later, separate audit of matt-harness's own three mechanisms
(`idea-audit` Phase 2, `compliance-audit` Phase 2, `deep-audit` Phase 3, `plan-reviewer.md`); no
changes to those surfaces are proposed here.

## TL;DR

- **Same-model self-correction reliably fails without an external, ground-truth-anchored
  signal — this is the single best-evidenced finding in the whole literature.**
  [Huang et al. (2023)](https://arxiv.org/abs/2310.01798) show GPT-3.5 keeps its first GSM8K
  answer 74.7% of the time when asked to self-correct with no outside feedback, and among the
  answers it *does* change, it flips correct→incorrect more often than incorrect→correct — net
  negative. Their multi-agent-debate replication (same paper, §4, Table 7) found 3-agent/2-round
  debate (6 model calls) scored 83.2% on GSM8K, barely above self-consistency at a *smaller*,
  3-call budget (82.5%). The table also has a matched 6-call self-consistency row whose value
  wasn't retrievable from the rendered source in this pass, so the strict like-for-like comparison
  (debate@6 vs. SC@6) isn't confirmed here — but even the retrievable comparison shows debate's
  headline number barely clearing a *cheaper* ensemble baseline, not a much larger one — debate
  among same-family instances looks close to free-riding on the ensemble effect, not doing
  independent adversarial work.
- **Cross-model / heterogeneous judging is the evidence-backed lever, not just a design
  preference.** [Zhang et al., "Stop Overvaluing Multi-Agent Debate" (2025)](https://arxiv.org/abs/2502.08788)
  ran 5 MAD methods × 9 benchmarks × 4 foundation models and found MAD *often fails to
  outperform* plain
  Chain-of-Thought/self-consistency at equal compute — but model heterogeneity is the one lever
  that consistently helped. Self-judging bias is mechanistically explained, not just observed:
  [Wataoka et al. (2024)](https://arxiv.org/abs/2410.21819) trace self-preference bias to
  *perplexity* — LLM judges score low-perplexity (familiar-to-them) text higher regardless of who
  wrote it — and a related, **unverified-in-this-pass** paper, ["Who Judges Matters"
  (2026)](https://arxiv.org/html/2609.17857) (found via WebSearch only, not fetched), reportedly
  extends the finding to same-*family* judges that never see their own output.
- **The literature's own effective designs converge on four recurring levers, worth using as
  comparison dimensions for any adversarial-dispatch design**: (1) an independent/fresh evaluation context
  that doesn't share the generator's own trace — CoVe's "factored" verification, AI Control's
  trusted-monitor pattern, AgentCoder's separate test-designer agent; (2) model or role
  heterogeneity — Stop-Overvaluing-MAD's antidote finding, AI Control's untrusted-vs-trusted
  model split, PyRIT's separate adversarial-chat-model-vs-target-model architecture; (3) a
  structural, non-freeform output contract — PyRIT's typed scorers (true/false, Likert,
  classification), garak's probe→detector pass/fail pipeline; (4) grounding in an external,
  checkable signal rather than the model's own say-so — Reflexion's self-generated-but-
  syntax-filtered test suites, MetaGPT's executable-feedback loop, CoVe's fact-check questions.
- **Red-teaming frameworks (PyRIT, garak, OpenAI's Red Teaming Network) are architecturally the
  closest published analogue to "attacker ≠ target," but their contract is different from a
  code/claim verifier**: they optimize for *finding at least one successful attack* (existence),
  scored by a typed scorer or classifier, not for *exhaustively judging a specific claim or diff*
  true/false. OpenAI's own whitepaper is candid about the limits: red teaming is
  "not a panacea for risk assessment," is "resource intensive," and findings decay as the target
  model changes — a point-in-time signal, not a standing gate
  ([OpenAI, 2025](https://arxiv.org/html/2503.16431v1), §4).
- **matt-harness already has in-repo primary-source research on the panel/jury question that
  directly bears on this topic and should not be re-derived**:
  `docs/research/tiered-multi-model-pipeline-audit-2026-08-21.md` cites a leaner 2-role
  reviewer+critic beating a heavier 4-role hierarchy by +5pp on SWE-bench Verified
  ([arXiv:2608.18167](https://arxiv.org/abs/2608.18167)), agreement quality *degrading* as review
  tiers climb ([TAO, arXiv:2506.12482](https://arxiv.org/abs/2506.12482)), and — most relevant to
  a same-family panel — that 9 frontier judges across 7 families carry only ~2 effective votes'
  worth of information, with the single best judge matching or beating the full panel
  ([arXiv:2605.29800](https://arxiv.org/abs/2605.29800)).

---

## 1. Critique-revise / debate-refine papers: what the primary sources actually say about failure modes

| Work | Mechanism | What makes it work, per the paper's own text | Documented failure mode |
|---|---|---|---|
| [Constitutional AI (Bai et al., Anthropic, 2022)](https://arxiv.org/abs/2212.08073) | Same model self-critiques then revises against a sampled constitutional principle (SL phase); a preference model trained on AI-labeled comparisons then drives RL (RLAIF) | §3.5 "Are Critiques Necessary?": critiqued revisions beat direct (critique-free) revisions **for smaller models**; for larger models the two "perform similarly, though critiques are always slightly better" | Same §3.5, verbatim: on inspecting the 52B model's own critiques, the authors "found that the critiques were sometimes reasonable, but **often made inaccurate or overstated criticisms**." The revision was usually still more harmless than the original — but the critique text itself wasn't reliable. This is same-model self-critique, not a cross-model check; the RL phase's preference model is the part that supplies an evaluation signal *external to the generator's own text*. |
| [Chain-of-Verification / CoVe (Dhuliawala et al., Meta, 2023)](https://arxiv.org/abs/2309.11495) | Draft → plan verification questions → answer them → produce a final revision | §3.3, verbatim: the paper explicitly runs verification with **"the LLM itself in all steps of CoVe, hence the model is used to check its own work"** — this is same-model, not cross-model. The paper defines a "factored" variant whose verification-answering step is given a context that "only contains the questions, and not the original baseline response," specifically so the check cannot copy the draft's own error (§3.3) — the paper's stated design intent, though this pass did not retrieve the joint-vs-factored ablation numbers to confirm the ranking empirically. Overall CoVe result: F1 improved 23% on MultiSpanQA; Wikidata list-task precision roughly doubled (0.17→0.36). | §3.3, verbatim on why "joint" is worse: because the verification questions and answers condition on the baseline response in the same context, **"the verification questions might hallucinate similarly to the original baseline response, which defeats the purpose."** I.e., letting a same-model checker see the thing it's checking, in the same context window, reproduces the original error — the paper's own stated reason for factoring the check into a separate, undistracted context. |
| [Reflexion (Shinn et al., NeurIPS 2023)](https://arxiv.org/abs/2303.11366) | Agent acts, receives task feedback, verbally self-reflects, stores the reflection in an episodic memory buffer for the next trial | For code tasks (§4.3) the paper is explicit that this needs a **grounded, external evaluation signal**: self-generated unit tests, produced via CoT, then **filtered for syntactic validity** before being trusted as the pass/fail oracle — the self-reflection text alone is not treated as sufficient. §2 (Related Work) explicitly contrasts itself with Self-Refine: "Self-Refine is effective but is **limited to single-generation reasoning tasks**." | Depends on an external grounding signal existing at all (compiler, test runner, environment reward) — the paper does not claim verbal self-reflection works without one. |
| [Self-Refine (Madaan et al., 2023)](https://arxiv.org/abs/2303.17651) | Single LLM plays generator, feedback-provider, and refiner, iteratively, no training | GPT-4+Self-Refine: +8.7 absolute points on Code Optimization (27.3%→36.0%). Best gains land on tasks with "more opportunities to miss some of the concepts on the first attempt" (e.g. Constrained Generation) — tasks with a large space of acceptable outputs. | For GSM8K math reasoning (Appendix O), the paper states it follows [Welleck et al. 2022] and **"uses the correct label to decide when to go from one point in the loop to the next"** — i.e. even Self-Refine's own math-reasoning results rely on an oracle ground-truth signal to know when to stop iterating, not on the model's self-assessment alone. |
| [Improving Factuality and Reasoning through Multiagent Debate (Du et al., 2023)](https://arxiv.org/abs/2305.14325) | Multiple instances of the *same* model propose answers and critique each other over rounds | Reduces some fallacious/hallucinated answers on math and strategy tasks vs. single-pass prompting, per the paper's own framing. | Not evaluated against an equal-compute self-consistency baseline in the original paper — that gap is exactly what the next row closes. |
| [Huang et al., "LLMs Cannot Self-Correct Reasoning Yet" (ICLR 2024)](https://arxiv.org/abs/2310.01798) | Direct replication of Du et al.'s debate method (3 agents, 2 rounds, 6 model calls) on GSM8K's full test set | — | §4, own table: Standard prompting 76.7% → Self-Consistency@3 82.5% → **Multi-Agent Debate (round 1, 6 responses) 83.2%** → Self-Consistency@6 comparable. Debate barely beats an equal-call-budget self-consistency ensemble of the *same* model. §3.3: without external ground truth, self-correction flips correct answers to incorrect ones more often than the reverse; the paper's mechanistic explanation is that the feedback prompt is an added instruction that can bias the model away from its own already-optimal first response, not toward a better one. |

**Read together**, these primary sources triangulate on one conclusion that none states as
cleanly alone: a same-model (or same-family, same-context) critique step tends to (a) inherit the
generator's own blind spots and errors, (b) sometimes make things worse without an external
anchor, and (c) barely outperform simply sampling the same model more times and voting — unless
either the check is run on a *fresh, separated context* (CoVe's factored variant) or the checking
signal is *external and mechanically checkable* (Reflexion's filtered tests, Self-Refine's oracle
label, Constitutional AI's human-trained preference model in the RL phase).

## 2. Does an LLM judging another LLM's output actually work — and does model identity matter?

| Work | Finding | Mechanism / evidence |
|---|---|---|
| [Zheng et al., "Judging LLM-as-a-Judge with MT-Bench and Chatbot Arena" (NeurIPS 2023)](https://arxiv.org/abs/2306.05685) — **found via WebSearch, not fetched in full in this pass** | The canonical source naming **position bias, verbosity bias, and self-enhancement bias** as the three documented LLM-judge failure modes; strong judges (GPT-4) reportedly reach >80% agreement with human preference, on par with human-human agreement, per the WebSearch summary | Introduces MT-Bench + Chatbot Arena as the benchmark used across most of the later self-preference-bias literature below |
| Fetched and read directly: [Wataoka et al., "Self-Preference Bias in LLM-as-a-Judge" (2024)](https://arxiv.org/abs/2410.21819) — full text: [arxiv.org/html/2410.21819v2](https://arxiv.org/html/2410.21819v2) | Quantifies self-preference bias directly and traces its **mechanism**: judges assign higher scores to lower-perplexity text — i.e. text the judge model itself finds "familiar" / likely to have generated — regardless of actual authorship | §6 Discussion, verbatim: proposes **"ensemble evaluation using multiple models"** and down-weighting a judge's score specifically on samples where that judge shows low perplexity, as the concrete mitigation |
| ["Who Judges Matters: Family-Conditioned Preference" (2026)](https://arxiv.org/html/2609.17857) — **found via WebSearch, not fetched in this pass** | Reported claim: judges show extra support for candidates from their own **model family even when the judge never evaluates its own literal output** | If confirmed, this would bear on any design where the judge and the generator share a vendor/training lineage but are different model instances — same-family bias, not only same-model bias; not independently verified here |
| ["Play Favorites" (2025)](https://arxiv.org/abs/2508.06709) | Reported via secondary WebSearch summary only, **not independently fetched and verified in this pass** — flagged per this file's own sourcing standard, not counted as confirmed | Reported claim: Claude judges boost scores for other Claude-family completions |
| [Greenblatt et al., "AI Control: Improving Safety Despite Intentional Subversion" (2023)](https://arxiv.org/abs/2312.06942) | Directly evaluates "trusted monitoring" (weaker, trusted model, e.g. GPT-3.5, reviews a stronger, untrusted model's, e.g. GPT-4, code for backdoors) vs. "untrusted monitoring" (a second instance of the same untrusted model reviews the first's output, with anti-collusion measures) | Abstract, verbatim: "using models to review the outputs of other models... researchers have not evaluated whether such techniques still ensure safety if the model is itself intentionally trying to subvert them"; finds that using the trusted model to edit or the untrusted model as a monitor (with collusion countermeasures) "substantially improves on simple baselines" — the paper's whole framing is that a same-model or same-capability-tier reviewer needs explicit anti-collusion design, it isn't safe by default |

This section is the direct evidentiary basis for why matt-harness's Codex-primary attacker
(cross-vendor, not just cross-instance, relative to the Claude orchestrator) is a stronger design
choice on paper than a same-family reviewer would be — not merely a stylistic preference. It also
surfaces a nuance worth carrying into the later audit: the bias literature's proposed mitigation
when cross-model isn't available is *ensemble + confidence down-weighting on familiar text*
(Wataoka et al.), not just "add more same-family judges" — which is consistent with the
in-repo finding (`tiered-multi-model-pipeline-audit-2026-08-21.md`) that a same-family panel
carries little more information than its single best judge.

## 3. Red-teaming frameworks: structure, pass/fail contract, and stated limits

| Framework | Architecture | Pass/fail contract | Attacker ≠ target, by design? |
|---|---|---|---|
| [Microsoft PyRIT](https://github.com/microsoft/PyRIT) ([paper, §III-A](https://arxiv.org/abs/2410.02828), [docs](https://microsoft.github.io/PyRIT/1.1.0/)) | Six components per the paper's own Fig. 1 (component names beyond what this pass confirmed in text: orchestrators, converters, scorers, targets, and memory — the paper states "six different components" but this pass did not retrieve the figure's full enumerated list, so it is not repeated in full here). Confirmed in text (§III-A6): the "Red Team Orchestrator" primes a separate **adversarial chat model** (e.g. GPT-4o) against a **target model**, optionally via half a dozen models composing a multi-turn attack; converters diversify attack phrasing. Demonstrated live against the Gandalf CTF chatbot (levels 1–4 extracted). | Scorers are typed and pluggable — **true/false, Likert-scale, or classification** — per the docs' "Flexible Scoring" description and the framework's own class names for LLM-driven self-ask scorers (confirmed via the project's own docs page, not the arXiv paper) — a structural output contract, not free text | Yes — architecturally separate adversarial-chat-model and target-model roles, explicit in the reference architecture diagram (paper, Fig. 2) |
| [NVIDIA garak](https://github.com/NVIDIA/garak) | `probes/` generate attack interactions, `detectors/` classify whether a failure mode appeared, `harnesses/` (default: `probewise`) wire each probe to its declared `primary_detector`/`extended_detectors`, `evaluators/` aggregate | Each probe declares its own detector(s); detectors are pluggable and can be string-match, classifier, or LLM-based — garak's README documents the plugin contract but leaves per-detector scoring semantics to each detector's own implementation | Not primarily an "attacker ≠ target model" design — garak is a scanner run *against* one target model with a library of adversarial probes, not a two-model adversarial dialogue by default |
| [OpenAI Red Teaming Network](https://openai.com/index/red-teaming-network/) (2023) | A standing roster of external domain experts engaged across a model's lifecycle, not a one-off pre-launch review — explicitly framed as a complement to, not replacement for, external audits | Human judgment, documented in system cards; no single structural pass/fail script | N/A — this is the human-in-the-loop counterpart to the automated frameworks above |
| [OpenAI's Approach to External Red Teaming, whitepaper (2025)](https://arxiv.org/html/2503.16431v1) | Documents the process (external experts get structured access, domain-specific risk taxonomies are co-developed, findings feed system cards) | — | — |
| Same whitepaper, §4 "Limitations and risks of red teaming" | — | — | Explicitly states red teaming is **"not a panacea for risk assessment"**; is **"resource intensive"** in time and cost; and findings from one point in time **may be "under-assessed or no longer reflected"** once the model or system is updated — i.e. it's a point-in-time signal that decays, not a standing gate |
| [OpenAI, "Diverse and Effective Red Teaming with Auto-Generated Rewards and Multi-Step RL" (2024)](https://arxiv.org/abs/2412.18693) | Automated: a *separate* red-teaming model is trained via RL to attack the target, using an LLM (e.g. GPT-4T) to brainstorm diverse attacker goals and rule-based rewards (RBRs) plus moderation models to grade whether an attack succeeded | Rewards come from a **different** judge (moderation model / rule-based reward), not the attacker model self-grading its own attack | Yes — attacker model, goal-brainstorming model, and success-grading model are kept separate specifically to avoid the attacker rubber-stamping itself |

The structural takeaway distinct from the critique/debate literature above: red-teaming
frameworks' contract is "does at least one attack succeed" (an existence search over a large
attack space), scored by a typed, mostly non-generative detector/scorer. That's a different shape
of problem from "is this specific claim/diff correct" (a bounded, structural-validation problem),
which is closer to what CoVe's factored verification, AI Control's trusted monitoring, and
AgentCoder's independent test designer are doing.

## 4. Real, shipped multi-agent coding systems with a separate checker/tester role

| System | Separation | Reported result | Independence caveat |
|---|---|---|---|
| [AgentCoder (Huang et al., 2023)](https://arxiv.org/abs/2312.13010) — abstract fetched; the numeric results below are from a **WebSearch summary of the paper, not independently confirmed against the full text in this pass** | Three distinct agents: **programmer**, **test designer** (per the paper's own abstract, designs tests "independently based on the coding requirements," i.e. not derived from the programmer's code), **test executor** (runs the test designer's tests against the programmer's code and reports results back) | Reported (WebSearch summary, not confirmed here): GPT-4 96.3% pass@1 HumanEval, 91.8% MBPP, at lower token overhead (56.9K/66.3K) than prior multi-agent baselines (138.2K/206.5K) | Test generation is decoupled from the coder's own code, per the abstract's own wording ("independently"). Reading this as a deliberate defense against the coder's tests encoding the coder's own blind spots is this file's own inference, not a claim the abstract makes explicitly. |
| [MetaGPT (Hong et al., 2023)](https://arxiv.org/abs/2308.00352) | Five roles (PM, Architect, Project Manager, Engineer, QA Engineer) under an SOP; an "executable feedback" loop has the **Engineer** write and run its own unit tests and debug against real execution results, not a separate reviewer's free-text critique | §4.4 ablation: adding executable feedback improved Pass@1 by +4.2 (HumanEval) and +5.4 (MBPP), and reduced "cost of human revisions" from 2.25 to 0.83 | This is **execution-grounded self-correction by the same Engineer role**, not an independent adversarial agent — the paper itself motivates it by noting non-executable self-reflection/review "still face[s] challenges in ensuring code executability," i.e. it upgrades the *grounding signal* (real test execution) rather than adding a second judging model. Worth distinguishing from AgentCoder's genuinely separate test-designer role above. |
| [AutoGen "Reflection" design pattern (Microsoft)](https://microsoft.github.io/autogen/stable//user-guide/core-user-guide/design-patterns/reflection.html) | Documented first-party pattern: a **coder agent** generates, a separate **reviewer agent** critiques, looping until a stopping condition (max iterations or reviewer approval) | Illustrative/documentation example, not a benchmarked result in this page | Named, official Microsoft pattern — the closest first-party framework documentation found to "second agent tries to break the first agent's output" as an explicit, reusable primitive, though the docs page itself is a tutorial, not a paper with numbers |

### Smaller GitHub projects surfaced but not counted as evidence

A WebSearch for open-source "adversarial verifier for AI coding agents" surfaces a cluster of very
recent, very small repos explicitly pitching this exact pattern: `Consecutive-Gen-AI/Agent-Proof-`
(0 stars, created 2026-09-14), `AndreaGriffiths11/proof-agent` (5 stars, created 2026-04-04),
`omeeragtoprak/agentic-engineering-protocol` (0 stars, created 2026-07-16) — confirmed via `gh api`
star counts and creation dates. These are noted because the pattern-language they use ("the worker
and the verifier are always separate agents," "self-verification is not verification") echoes the
literature above closely, but given near-zero stars and days-old creation dates they are **surfaced,
not counted as adopted, shipped systems** — the same standard this repo's convention file
(`typesafe-ai-system-one-jev-2026-09-18.md`) applies to unfetched or low-signal sources. A prior
matt-harness research pass already found one genuinely adopted, real-world example of this exact
pattern independently: `coldteadotai/abide` (105 stars), which uses an LLM (TypeSafe's Jev) as a
separate judge against a coding agent's edits, and — notably — reported its own precision honestly
(26% edit-level) rather than rounding it up; see
`docs/research/typesafe-ai-system-one-jev-2026-09-18.md` for the full write-up, not re-derived here.

## 5. Cross-reference: matt-harness's own prior research on this exact question

Two in-repo research docs, found via `qmd` before this pass and not re-derived:

- `docs/research/tiered-multi-model-pipeline-audit-2026-08-21.md` — already collects primary
  sources directly bearing on "does an extra adversarial/review tier help": a leaner **2-role
  reviewer+critic** setup beating a heavier 4-role hierarchy by +5pp on SWE-bench Verified
  ([arXiv:2608.18167](https://arxiv.org/abs/2608.18167)); a real 3-tier healthcare escalation
  system where agreement quality **degraded** climbing tiers, 85.0%→70.1%
  ([TAO, arXiv:2506.12482](https://arxiv.org/abs/2506.12482)); a 4-model jury beating
  self-consistency resampling by +26.7pp at 8x lower budget
  ([arXiv:2607.10139](https://arxiv.org/abs/2607.10139)) — but with a same-day correction noting
  that finding assumed *error-diverse, cross-family* panels; and, most relevant to any
  same-vendor panel design, that 9 frontier judges across 7 families carry only ~2 effective
  votes' worth of independent information, with the single best judge matching or beating the
  full panel in every tested condition ([arXiv:2605.29800](https://arxiv.org/abs/2605.29800)).
- `docs/research/harness-engineering-2026-04-critique-cost.md` — an adversarial review of a
  third-party harness-engineering article that independently names the same circularity this
  file's §2 documents empirically: "a judge with the generator's blind spots cannot catch those
  blind spots," flagged there as an unaddressed gap in that article's own "LLM as judge"
  endorsement.

## What could not be verified in this pass

- The exact "Play Favorites" (arXiv:2508.06709) same-family score-boosting numbers — reported only
  via WebSearch summary, not fetched and read directly; flagged in §2, not counted as confirmed.
- Per-detector scoring semantics inside garak (string-match vs. classifier vs. LLM-judge, and
  whether any produce a continuous score vs. strict boolean) — the README documents the plugin
  *contract* (each probe declares its detectors) but not an exhaustive account of every detector's
  internal scoring method; would need `reference.garak.ai` or the source tree, not fetched here.
- Whether InfoWorld-style independent, non-PR-rewrite coverage exists of any of the small GitHub
  "adversarial verifier" repos in §4 — none was found, consistent with their near-zero star counts
  and days-old creation dates.
- The Constitutional AI paper's RL/RLAIF phase preference-model training details beyond what's
  needed for this file's claim (that it supplies an external-to-the-generator signal) — a full
  treatment of RLAIF mechanics was out of scope here.

## Sources

- [Constitutional AI: Harmlessness from AI Feedback (arXiv:2212.08073)](https://arxiv.org/abs/2212.08073) — full text: [arxiv.org/html/2212.08073v1](https://arxiv.org/html/2212.08073v1)
- [Chain-of-Verification Reduces Hallucination in LLMs (arXiv:2309.11495)](https://arxiv.org/abs/2309.11495) — full text: [arxiv.org/html/2309.11495v2](https://arxiv.org/html/2309.11495v2)
- [Reflexion: Language Agents with Verbal Reinforcement Learning (arXiv:2303.11366)](https://arxiv.org/abs/2303.11366) — full text: [arxiv.org/html/2303.11366v4](https://arxiv.org/html/2303.11366v4)
- [Self-Refine: Iterative Refinement with Self-Feedback (arXiv:2303.17651)](https://arxiv.org/abs/2303.17651) — full text: [arxiv.org/html/2303.17651v2](https://arxiv.org/html/2303.17651v2)
- [Improving Factuality and Reasoning through Multiagent Debate (arXiv:2305.14325)](https://arxiv.org/abs/2305.14325)
- [Large Language Models Cannot Self-Correct Reasoning Yet (arXiv:2310.01798)](https://arxiv.org/abs/2310.01798) — full text: [arxiv.org/html/2310.01798v2](https://arxiv.org/html/2310.01798v2)
- [Stop Overvaluing Multi-Agent Debate (arXiv:2502.08788)](https://arxiv.org/abs/2502.08788) — full text: [arxiv.org/html/2502.08788v3](https://arxiv.org/html/2502.08788v3)
- [Judging LLM-as-a-Judge with MT-Bench and Chatbot Arena (arXiv:2306.05685)](https://arxiv.org/abs/2306.05685) — found via WebSearch, not fetched in full
- [Self-Preference Bias in LLM-as-a-Judge (arXiv:2410.21819)](https://arxiv.org/abs/2410.21819) — full text: [arxiv.org/html/2410.21819v2](https://arxiv.org/html/2410.21819v2)
- ["Who Judges Matters": Family-Conditioned Preference (arXiv:2609.17857)](https://arxiv.org/html/2609.17857) — found via WebSearch, **not fetched**, not independently confirmed
- ["Play Favorites": Statistical Method to Measure Self-Bias (arXiv:2508.06709)](https://arxiv.org/abs/2508.06709) — found via WebSearch, **not fetched**, not independently confirmed
- [AI Control: Improving Safety Despite Intentional Subversion (arXiv:2312.06942)](https://arxiv.org/abs/2312.06942)
- [AgentCoder: Multi-Agent-based Code Generation (arXiv:2312.13010)](https://arxiv.org/abs/2312.13010)
- [MetaGPT: Meta Programming for a Multi-Agent Collaborative Framework (arXiv:2308.00352)](https://arxiv.org/abs/2308.00352) — full text: [arxiv.org/html/2308.00352v6](https://arxiv.org/html/2308.00352v6)
- [Microsoft PyRIT — GitHub](https://github.com/microsoft/PyRIT), [PyRIT paper (arXiv:2410.02828)](https://arxiv.org/abs/2410.02828), [docs](https://microsoft.github.io/PyRIT/1.1.0/)
- [NVIDIA garak — GitHub](https://github.com/NVIDIA/garak)
- [OpenAI Red Teaming Network (2023)](https://openai.com/index/red-teaming-network/)
- [Advancing red teaming with people and AI (OpenAI, 2024)](https://openai.com/index/advancing-red-teaming-with-people-and-ai/)
- [OpenAI's Approach to External Red Teaming for AI Models and Systems (arXiv:2503.16431)](https://arxiv.org/html/2503.16431v1)
- [Diverse and Effective Red Teaming with Auto-Generated Rewards and Multi-Step RL (arXiv:2412.18693)](https://arxiv.org/abs/2412.18693)
- [AutoGen "Reflection" design pattern — Microsoft docs](https://microsoft.github.io/autogen/stable//user-guide/core-user-guide/design-patterns/reflection.html)
- Small GitHub repos surfaced, not counted as evidence: [Consecutive-Gen-AI/Agent-Proof-](https://github.com/Consecutive-Gen-AI/Agent-Proof-), [AndreaGriffiths11/proof-agent](https://github.com/AndreaGriffiths11/proof-agent), [omeeragtoprak/agentic-engineering-protocol](https://github.com/omeeragtoprak/agentic-engineering-protocol)
- In-repo prior research (not re-derived): `docs/research/tiered-multi-model-pipeline-audit-2026-08-21.md`, `docs/research/harness-engineering-2026-04-critique-cost.md`, `docs/research/typesafe-ai-system-one-jev-2026-09-18.md`
