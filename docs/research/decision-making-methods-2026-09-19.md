# Decision-Making Methods — Drill-Down Research and Application to mh (2026-09-19)

Five parallel senior research lanes (opus, primary-source-only) drilled into decision-making
methods: normative scoring, behavioral debiasing, organizational frameworks, software-engineering
decision records, and LLM-judge calibration. A sixth input — the user-supplied TypeSafe.ai docs —
is folded in as external validation. This file synthesizes all six, audits mh's own decision
doctrine against them, and scores what's worth building.

**Headline finding, before anything else:** matt-harness's own doctrine contains an uncited,
overstated claim, independently flagged by two of the five lanes and confirmed against the repo's
own history by the author of this synthesis. See §2 — it is the single most important thing this
research turned up, because it is about the repo's own credibility on exactly the topic it was
researching.

**Verification note.** Every citation below was traced by its lane to a primary source (author's
own text, the owning org's own page, or a fetched paper) unless marked `[not fetched]` /
`[unconfirmed]`, in which case the flag is preserved rather than smoothed over. A live spot-check
(this session, not a lane) independently re-derived §2's provenance chain from `CHANGELOG.md` and
the auto-memory store and confirmed it.

---

## 1. Research findings

### 1.1 Normative / quantitative scoring — MCDA, weighted-sum, AHP, anchored rubrics

Multi-criteria decision analysis (MCDA) has three lineages:

- **Additive weighted-sum** (Keeney & Raiffa 1976) — the family Rule 14 actually belongs to.
  `V(a) = Σ wᵢ·vᵢ(a)`. **Dawes (1979)**, "The robust beauty of improper linear models in decision
  making," and **Grove et al. (2000)**'s 136-study meta-analysis both show linear models with
  *unit or near-arbitrary weights* perform nearly as well as carefully elicited ones — "the whole
  trick is to know what variables to look at and then know how to add." **Implication: which
  criteria to score matters far more than how precisely the weights are tuned.**
- **AHP** (Saaty 1977/1990) — pairwise comparisons, a principal-eigenvector weight derivation, and
  a computed **consistency ratio (CR < 0.10)** that flags self-contradictory judgments. Genuinely
  contested: Belton & Gear (1983) showed rank reversal, Dyer (1990) argued the 1–9 verbal scale has
  no coherent preference theory behind it. **The one idea worth stealing without adopting AHP
  wholesale: a computed consistency/contradiction check — Rule 14 has no analogue of this today.**
- **Outranking (ELECTRE/PROMETHEE)** — refuses to force a single score; permits a **veto
  threshold**, where one criterion blocks an otherwise-favorable conclusion. This is the same shape
  as `idea-audit`'s fatal-weakness floor and `plan-reviewer`'s Critical/High blocking gate — **a
  genuine, independent convergence with the literature, worth naming explicitly.**

**Confidence in MCDA is derived, never declared.** AHP's CR, weight-sensitivity analysis (does the
ranking survive a weight perturbation?), and SMAA's stochastic acceptability indices (Lahdelma,
Hokkanen & Salminen 1998) are all *computed from the judgments*, not self-reported. Rule 14's
confidence field has no such mechanism — it is a bare model self-report, the weakest form the
broader literature recognizes (§1.5).

### 1.2 Behavioral debiasing — pre-mortem, WRAP, and the classical bias lineage

**Pre-mortem (Klein).** Two separable mechanisms: (a) **prospective hindsight** — an individual
cognitive effect (imagining failure as certain changes causal search), evidenced by Mitchell,
Russo & Pennington (1989), though the famous "30% more accurate" restatement is a
quantity-of-reasons result mis-cited as an accuracy result; and (b) **social permission to
dissent** — a group effect, and the one Klein himself leads with ("silent pressure … not to
surface doubts"). **For a solo engineer or single AI agent, (b) is null — there is no silenced
dissenter to unmute.** The empirical news is better than that framing suggests: Keysor, Wojtyna &
Veinott (2020) directly tested individual vs. group pre-mortem and found **no significant
difference on confidence reduction** (F(1,42)=0.85, p=.772) — the surviving mechanism doesn't need
a group. What *does* need a group is risk-*coverage* (Gallop et al. 2016, teams-vs-teams only). The
field's own handbook (Soll, Milkman & Payne 2015) says "more research is needed" and never mentions
Klein or "mortem" once in its full text.

**WRAP** (Heath & Heath, *Decisive*, 2013) is a checklist over separately-evidenced techniques, not
a validated intervention as a whole. Its four steps degrade unevenly for a solo decision-maker:
**W**(vanishing-options, multitracking) and **A**/**P**(10/10/10, ranges not points, **tripwires**)
survive solo almost fully; **R**(devil's advocate, "ask your team for 3 alternatives") is the most
group-dependent step. **Tripwires — dates/metrics/budgets as pre-commitment re-decision
triggers — are the single most transferable and most mechanically-checkable WRAP technique.**

**Bias lineage** (built on `llm-wiki`'s existing brief, which it corrects on 2 points): System 1/2
are Stanovich & West's (2000) terms, not Kahneman's own coinage; Arkes & Blumer (1985) — the actual
naming paper for the sunk-cost effect — is missing from the wiki entirely. Soll, Milkman & Payne
(2015) supplies the debiasing-*technique* evidence layer the wiki lacks: **"decision readiness"**
(fatigue, distraction, visceral state degrade whether System 2 can even apply a known framework)
and **"cognitive repairs"** — organizational routines like "colleagues trained to criticize and
poke holes" — which is a direct citation for mh's own maker/verifier split.

**General pattern:** techniques that redirect one mind's attention (prospective hindsight, 10/10/10,
ranges-not-points) port to a solo agent; techniques that work by changing the *social cost* of
dissent (pre-mortem's group half, devil's advocate) do not port at all — recovering them requires
an actual second, independently-contexted party.

### 1.3 Organizational frameworks — RAPID, DACI, Cynefin, OODA, one-way/two-way doors

Five frameworks, five different questions — they compose, they don't compete:

| Framework | Question it answers | Originator's own stated scope limit |
|---|---|---|
| **RAPID** (Bain; Rogers & Blenko, HBR 2006) | Who decides? | High-value/high-frequency decisions only; "Agree" roles assigned sparingly or the framework becomes a consensus veto |
| **DACI** | Who decides? (lighter than RAPID) | **None — no originator exists.** Atlassian explicitly disclaims inventing it ("DACI isn't something we invented"); the "Intuit 1980s" story is uncited internet folklore (Forbes 2019 hedges it as "legend"). Atlassian's own caveat: "don't wallow in them." |
| **Cynefin** (Snowden; Kurtz & Snowden 2003) | What kind of problem is this? | Explicitly **not** a categorization model, **not predictive**, and its value is "not evidential" — a sense-making tool for group discourse, not a solo classifier to run in your head |
| **OODA** (Boyd) | How do I adapt faster than a reacting adversary? | **Not a sequential 4-step loop** — Boyd's own sketch wires Orient directly to both Observe and Act; "faster" is not the point, *orientation* is. Domain is time-competitive adaptation against something that also moves — reduces to an ordinary feedback loop outside that |
| **One-way / two-way doors** (Bezos, 2015 letter) | How much process does this decision deserve? | **Asymmetric, per Bezos's own footnote 1**: "companies that habitually use the light-weight [two-way] process to make [one-way] decisions go extinct before they get large." No test is given for *which type* a decision is — that's the hard part, left unsolved |

Two corrections worth carrying: **"disagree and commit" is a separate concept from one-way/two-way
doors** — they just sit side-by-side in the same Bezos letter section, which is why they get
conflated. And its usual "Andy Grove, 1983" attribution is secondary-only (nothing published before
2003); the earliest documentary trace of the literal phrase is **Scott McNealy at Sun**
(Southwick 1999; "agree and commit, disagree and commit, or get out of the way"). Bezos's own 2016
example inverts the usual direction — the CEO commits to the team's call, not a subordinate to the
boss's.

**Rule 1's triad already implements a compressed version of the door test + Cynefin's "what kind of
problem" question**, without naming either.

### 1.4 Software-engineering decision records — ADRs, RFCs, design docs, "disagree and commit"

**Nygard's original ADR** (2011): five sections (Title/Context/Decision/Status/Consequences),
one page, prose ("a conversation with a future developer"), **all** consequences listed including
negative ones, and immutability — "if a decision is reversed, we keep the old one around, but mark
it superseded." He *popularized*, not invented, decision records (practice traces to the late
1990s per Zdun/Zimmermann). **MADR** (current: 4.0.0) is the dominant derivative and fixes the two
things Nygard's format has **no slot for at all**: rejected alternatives (`Considered Options`) and
a compliance check (`Confirmation`); it moves `Status` into YAML frontmatter, adding a `rejected`
value Nygard never had.

**Rust vs. Python RFC processes diverge sharply on the rejected-decision artifact**: Rust closes
rejected RFC PRs (rationale buried in threads); Python keeps Rejected PEPs permanently published
*specifically to prevent re-litigating the same idea*. **Google design docs** (Ubl 2020) are
pre-decision proposals under review, not post-decision records — `Alternatives Considered` and
`Non-Goals` are load-bearing sections, and the review step's justification is pure cost-of-change
economics ("cheap to change earlier").

**"Disagree and commit" is not one-way/two-way doors** — it's about what a dissenter does *after*
a decision, not about how reversible the decision is. Its origin is contested (Sun/McNealy has
earlier documentary evidence than Intel/Grove), and its *meaning* shifts by speaker: McNealy's
version enforces commitment by exit ("or get out of the way"); Grove's (via secondaries) is
subordinates committing after open debate; Bezos's flagship 2016 example runs it **upward — the
CEO committing to the team**, the opposite direction from Amazon's own Leadership Principle text.

**This repo's own ADRs (0001–0003) are a Nygard/MADR hybrid**: keeps Nygard's numbering,
immutability, prose voice, and (executed unusually literally) the all-consequences rule; imports
MADR's rejected-alternatives analysis (`## Considered options` / `## Rejected: …`); drops both
formats' `Status`/`Context`/`Decision` skeleton entirely. **The one real gap: no machine-readable
status field** — 0002's supersession is discoverable only by reading its first paragraph.

### 1.5 LLM-judge calibration — rubric anchoring, self-grading circularity, confidence

**LLM-as-judge is real but narrower than assumed.** Zheng et al. (2023, NeurIPS) — the founding
paper — found GPT-4-judge matches human agreement >80% **on open-ended chat preference**, not on
scoring against a weighted engineering rubric; that transfer is an assumption. Its four documented
limitations differ sharply in strength: **position bias** and a **10-question math-grading failure
(Claude/GPT-3.5 wrong 91.3% of the time; GPT-4 only 8.7%)** are strongly evidenced; **self-
enhancement bias is not** — the paper explicitly states "our study cannot determine whether the
models exhibit a self-enhancement bias." The math-grading failure is the most under-cited and most
relevant to mh: **a judge can fail to grade a criterion it could solve directly, anchored by the
candidate's own stated reasoning** — any rubric criterion needing independent re-derivation (a cost
estimate, a count, a complexity claim) inherits this.

**Self-grading circularity has a real direct source**: Panickssery, Bowman & Feng (2024), "LLM
Evaluators Recognize and Favor Their Own Generations" — confirmed exactly as hypothesized, with a
measured linear correlation between self-recognition capability and self-preference strength.
Mechanism (Wataoka et al. 2024): judges favor **lower-perplexity, more-familiar-looking text**,
regardless of authorship. **This means fresh context (as `ideate-critic` uses) mitigates process
exposure but cannot remove text-recognizability** — `ideate-critic.md`'s own caveat ("fresh context
mitigates but does not eliminate shared blind spots") is *exactly right*, not hedging. The stronger
mitigation the literature endorses is **cross-family judging** (a different model class) — which mh
already has, via Codex dispatch — a fact worth stating explicitly as the primary mitigation, with
fresh-context critique as the secondary one.

**Confidence: self-reported is weak, but the specific mh claim comparing it to Jev overreaches.**
Verbalized LLM confidence is well-documented as overconfident (Xiong et al. 2023, ICLR). But
`haiku-decision-calls.md`'s claim that a self-report is "weaker than even Jev's own confidence
field" is not supported — Tian et al. (2023) found RLHF models' *verbalized* confidence can be
**better** calibrated than their own conditional probabilities, and Jev's confidence field is
itself just normalized peakedness of a probability distribution `(p_max−1/K)/(1−1/K)`, not a
measured-against-outcomes calibration score. **Neither is a measured calibration; neither should
gate a decision alone.** `ideate-critic`'s existing `confidence: {level, reason}` — a coarse band
plus a stated reason, not a decimal — is closer to what the literature actually supports than a
raw self-reported number would be.

### 1.6 External validation — TypeSafe.ai patterns (user-supplied, folded in)

Three pages from `docs.typesafe.ai`, fetched mid-research at the user's request, independently
validate two things mh already does and name them:

- **Composite Scoring** = an LLM scores each *atomic* dimension against an anchored rubric (0–4,
  worked example per level), and a **separate deterministic script** normalizes and applies
  weights — the model never does the arithmetic. This is exactly `ideate-critic` (scores) +
  `rank.py` (combines), and `plan-reviewer` (scores) + `plan-verdict-check.py` (gates). Independent
  external confirmation of the pattern, with a name attached.
- **Confidence-Gated Routing** = a 3-tier bucket (act automatically / confirm-or-flag / route to a
  human) on a confidence axis, with the explicit caveat that thresholds are domain- and
  model-specific and must be tuned empirically, never fixed. Matches Rule 14's "insufficient data →
  block on operator" posture and Bain/Bezos's own reversibility-gated escalation.
- **System One** (Jev): a *trained, calibrated classifier*, not an LLM — its probabilities are
  optimized against real outcomes. This is structurally different from anything mh's Claude-based
  agents can produce (confirmed independently by `haiku-decision-calls.md`: the Messages API has no
  logprobs). It does not change any build recommendation below — mh has no consumer for a TypeSafe
  integration and one was already declined for lack of a named consumer
  (`docs/research/haiku-jev-decision-primitive-2026-09-18.md`) — but it sharpens *why* mh's
  confidence field will always be self-report, not a measured statistic, absent a different
  underlying model.

---

## 2. Doctrine-accuracy correction — Rule 14's "external benchmark" claim

**The claim, appearing near-verbatim in three files** (`docs/METHODOLOGY.md:34`,
`agents/plan-reviewer.md:139-141`, `skills/workflow/idea-audit/SKILL.md:266-268`): *"an external
benchmark found a subjective, example-free rule scoring far worse than an anchored one on identical
inputs."*

**Two research lanes independently flagged this as unsupported as written; a live spot-check in
this session traced and confirmed the actual source, resolving a discrepancy between the two
lanes' findings:**

- Lane 5 traced it correctly: `CHANGELOG.md` v1.1.99 → auto-memory `jev-typesafe-usecase-survey-
  2026-09-19.md` → `github.com/coldteadotai/abide`'s replay benchmark
  (`benchmarks/replay/README.md`).
- Lane 1 missed this connection and reported finding nothing in `CHANGELOG.md`, concluding only an
  uncited vendor glossary page (futureagi.com) matched the claim's *shape*.
- **This session re-fetched `CHANGELOG.md` v1.1.99 directly and confirmed lane 5's trace is
  correct**: it documents "a 5-agent audit … applying an external LLM-rubric benchmark's failure
  pattern (unscoped/subjective criteria cause false positives, not model choice)" — and that
  benchmark is `abide`'s.

**What `abide`'s benchmark actually measured, and why the doctrine overstates it:**

`abide` replayed 93 real Claude Code sessions and judged them with its own rubric (judge model:
Jev). Overall edit-level precision: 26% (39 flagged, 10 confirmed). Two badly-scoped rules
(`comment-volume`, `plain-error-for-expected-failure`) accounted for most of the misses — 1/11 and
2/10 — against well-scoped rules at 3/3, 3/3, 6/8. The author's own diagnosis: these two rules
needed a path `scope` and were subjective by nature, not missing a worked example — and the
numbers were taken *before* the tool's own calibration step (`abide calibrate`/`tune`) had run.

Three specific overstatements in the doctrine's wording:
1. **"On identical inputs" is false** — each rule judged a different set of hunks; there is no
   paired A/B on the same input.
2. **The actual failure mode was scope/subjectivity, not the absence of worked examples** —
   "a criteria example" appears once, as a *proposed, unrun* fix idea, not a measured intervention.
3. **`abide`'s rules are binary yes/no per rule; Rule 14's mechanism (one worked example per level
   on a multi-level score) is a different construct** than anything this benchmark tested.

**The controlled experiment that does exist for the actual claim partially contradicts it.**
Zheng et al. (2023), App. D.2: adding few-shot examples to a judge prompt raised **position-swap
consistency** substantially (Claude-v1 23.8%→63.7%, GPT-4 65.0%→77.5%) — but the paper's own next
sentence: few-shot GPT-4 "performs similarly to zero-shot" **on agreement with humans**. Genuine
support exists elsewhere: Jönsson & Svingby (2007), reviewing 75 studies, found rubric reliability
improves when rubrics are "analytic, topic-specific, and complemented with exemplars" — almost
exactly Rule 14's own prescription — but the classical BARS lineage this descends from (Landy &
Farr 1980) found rating *format* explains only a small fraction of rating variance and called for a
moratorium on the whole research program. A 2026 paper (Roy et al., PReMISE) even found **more
operationally specific rubrics were *more* exploitable** — anchoring buys agreement, not validity.

**Recommended fix**, drafted by lane 5 and independently endorsed by lane 1's separate finding:

> Each criterion needs one worked example per level, not a bare label. Evidence is mixed: rubric
> reliability improves when rubrics are analytic, topic-specific and carry exemplars (Jönsson &
> Svingby 2007, 75 studies), though format alone explains little rating variance in the classical
> literature (Landy & Farr 1980). For LLM judges, few-shot examples raised judge self-consistency
> substantially but did not improve agreement with humans (Zheng et al. 2023, App. D.2). Anchoring
> buys reproducibility, which a re-runnable gate needs; it is not established to buy correctness.

`docs/METHODOLOGY.md` has a 4096-byte pre-commit cap (per `CLAUDE.md`), so the fix must split: the
doctrine line becomes one short, honestly-hedged sentence, and the full cited paragraph goes in a
new `docs/reference/` file that `plan-reviewer.md` and `idea-audit/SKILL.md` point to (neither of
those two files has a byte cap). See §4/§5.

---

## 3. mh's existing decision-making infrastructure (inventory)

| Component | What it already does | Nearest research lineage |
|---|---|---|
| **Rule 1** (`METHODOLOGY.md`) — one-way door / blast radius / riskiest assumption | Triage triad before any non-trivial act | Bezos one-way/two-way doors; Cynefin's "what kind of problem" question |
| **Rule 13** — delegation, 5-agent cap, `NEEDS-DECISION`, `Ruling: what–why–cost` | Escalation shape for subagent-surfaced decisions | RAPID's single-Decider constraint (informally) |
| **Rule 14** — score not feel: criteria, weights, numeric result, reason, confidence, worked-example-per-level | mh's own MCDA-shaped weighted-sum scoring mandate | Weighted-sum MCDA (Keeney & Raiffa); BARS (Smith & Kendall) — **but see §2, its own citation is broken** |
| `operating-model.md` #2 — maker never grades own work | Fresh-context validators; read-only reviewer agents | Self-preference bias (Panickssery 2024); cross-family Codex dispatch is the literature's actual preferred mitigation |
| `operating-model.md` #3 — evidence order: deterministic → trajectory → track record → confidence | Explicitly ranks confidence *last*, as the weakest evidence | Matches the calibration literature's own verdict on self-reported confidence |
| `agents/plan-reviewer.md` — 8-lens **fatal-weakness floor**, not a blended score; severity anchors; `verdict_movers`/`revisit_if` | A non-compensatory (conjunctive) decision rule | Outranking/ELECTRE veto threshold — independent convergence; `revisit_if` ≈ WRAP's tripwire concept, unnamed |
| `agents/ideate-critic.md` + `rank.py` | Novelty/viability/fit scored by the LLM, **combined by a deterministic script**; `confidence: {level, reason}` coarse band, not a decimal; explicit anchoring-bias guard in its own procedure | TypeSafe's "Composite Scoring" pattern, independently named; the coarse-band confidence shape the calibration literature actually supports |
| `docs/reference/haiku-decision-calls.md` | Cheap single-decision primitive; explicitly rejects manufacturing a confidence field | Xiong et al. overconfidence finding — correct on the core advice, overreaches on one comparative claim (see §2 sibling finding, §4) |
| `docs/adr/0001-0003` | Nygard/MADR hybrid; rejected-alternatives sections; immutable, superseded-not-deleted | Nygard 2011 + MADR 4.0.0 — missing MADR's machine-readable `status` field |
| `scripts/_lib/plan-verdict-check.py` | Mechanically checks plan-reviewer's self-consistency (no `production-ready` alongside a real blocker) | The same "don't trust a self-graded verdict" principle as the maker/verifier split |

**What's absent today, per the research:** a computed weight-sensitivity or consistency check
(AHP's CR / Dawes's robustness result has no analogue); any tracking of stated confidence against
actual outcomes (Brier-style, which would turn confidence from decoration into evidence, matching
`operating-model.md`'s own stated evidence order); a machine-readable ADR status field; and an
explicit, citation-correct statement of *why* the anchored-rubric requirement holds (§2).

---

## 4. Scored recommendations

Rule 14 requires "important" decisions — one the user asked to rank — to carry stated criteria,
weights, a numeric result, a pass/fail reason, and confidence, with one worked example per rubric
level. Per this research's own finding (§1.1, §2), dense per-level anchoring helps most for
*topic-specific* criteria and adds little for general ones — so three broad criteria get anchors at
low/mid/high rather than at all 11 points.

**Criteria and weights** (weights follow Dawes 1979's finding that criteria selection matters far
more than weight precision — these are round numbers, not fitted):

| Criterion | Weight | 0 (low) | 5 (mid) | 10 (high) |
|---|---|---|---|---|
| **Evidence strength** | 0.30 | Folk claim, no primary source found | Real study, but conditional/mixed/thin (n<50, one domain) | Multiple converging primary sources, or a large systematic review |
| **Ease of integration** | 0.35 | Needs new persistent infra, a new agent, or a doctrine-wide rewrite | A new script or prompt file, no new infra | A wording/framing change to an existing field, zero new code |
| **Marginal value** | 0.35 | mh already does this under another name | Real gap, narrow blast radius if wrong | Real gap, and getting it wrong currently produces a false-confidence failure mode |

Threshold: **≥7.0 weighted → build now; [5.0, 7.0) → build if cheap, otherwise backlog; <5.0 →
don't build.** (Row 5 below scores 6.95 — inside the "build if cheap" band, not a ≥7.0 call; a
plan-reviewer pass on this research's own follow-up plan caught an earlier draft misreading it as
one.)

| # | Recommendation | Evidence | Ease | Value | Weighted | Verdict | Confidence |
|---|---|---:|---:|---:|---:|---|---|
| 1 | **Fix the uncited "external benchmark" claim** (§2) in all 3 files + add a cited `docs/reference/` companion | n/a — this is a correctness fix, not a build tradeoff | — | — | — | **Do regardless, first** | 90% — the mis-citation is confirmed, not disputed |
| 2 | Weight-sensitivity check script (does the verdict flip under a plausible weight perturbation?) | 7 | 8 | 7 | **7.35** | Build | 70% |
| 3 | Confidence bands (`{level, reason}`, not a decimal) in Rule 14 + `haiku-decision-calls.md`, plus a lightweight log of stated confidence vs. later outcome | 9 | 5 | 8 | **7.25** | Build | 75% |
| 4 | Machine-readable `status`/`supersedes` YAML frontmatter on `docs/adr/*.md` | 8 | 9 | 6 | **7.65** | Build | 85% |
| 5 | Name the existing outranking/veto convergence (`plan-reviewer`, `idea-audit` fatal floors) explicitly in doctrine — doc-only | 8 | 10 | 3 | **6.95** | Build (cheap, do while writing #1) | 85% |
| 6 | Frame `plan-reviewer`'s `revisit_if` field explicitly as a WRAP tripwire (a date/metric/count, not a vague condition) — doc-only guidance | 6 | 10 | 4 | **6.70** | Build (cheap) | 80% |
| 7 | Solo pre-mortem prompt template ("assume this plan failed; past tense; list why") for `plan-reviewer`/`code-architect` use | 5 | 9 | 5 | **6.40** | Backlog | 55% — thin evidence (n=43 null result) |
| — | AHP full pairwise-comparison adoption | 3 (disputed: rank reversal, no coherent preference theory per Dyer 1990) | 2 (n(n−1)/2 judgments per level) | 3 | ~2.7 | **Reject** | 80% this is correctly rejected |
| — | Cynefin domain pre-check as a routing gate | 4 | 5 | 4 | ~4.3 | **Reject** — Snowden's own text says Cynefin is explicitly *not* a categorization model to run a solo classifier against | 75% |
| — | RAPID/DACI formal role tags in `spawn-brief.md` | 4 | 6 | 3 | ~4.3 | **Defer** — `NEEDS-DECISION` already gives a single escalation path; DACI has no evidence base of its own (§1.3) to justify formalizing further | 60% |

---

## 5. Actionable changes

1. **Fix the citation** (Recommendation 1). Edit `docs/METHODOLOGY.md:34`,
   `agents/plan-reviewer.md:139-141`, `skills/workflow/idea-audit/SKILL.md:266-268` to the hedged,
   defensible wording in §2, and add a new `docs/reference/rubric-anchoring-evidence.md` carrying
   the full citations (Jönsson & Svingby 2007, Landy & Farr 1980, Zheng et al. 2023 App. D.2, PReMISE
   2026) that the three call-sites point to. Also hedge `haiku-decision-calls.md:59`'s "weaker than
   even Jev's own confidence field" — the ranking isn't supported (§1.5); replace with "neither is a
   measured calibration; neither should gate a decision alone."
2. **Weight-sensitivity script** — a small script alongside `rank.py`/`plan-verdict-check.py` that
   takes a criteria/weight/score breakdown and reports whether the verdict is stable under a stated
   weight perturbation (e.g. ±20%). Flags a "fragile" verdict as its own finding, not silently.
3. **Confidence-band propagation** — change Rule 14's confidence field, and `haiku-decision-calls.md`'s
   guidance, to require `{level: high|medium|low, reason}` (matching `ideate-critic`'s existing
   shape) instead of a bare self-reported number; add a small append-only log (one line per scored
   decision: stated confidence, later outcome if known) so confidence becomes checkable evidence
   over time, matching `operating-model.md`'s own stated evidence order.
4. **ADR frontmatter** — add `status:` (`accepted`/`superseded by ADR-NNNN`/etc.) to
   `docs/adr/0001-0003`, MADR-style, closing the "which ADRs are still in force" gap lane 4 found.
5. **Doc-only wins** (Recommendations 5–6) — fold into the same doctrine edit as #1: name the
   fatal-weakness-floor/veto convergence with the outranking-methods literature, and reframe
   `revisit_if` explicitly as a tripwire (a date, metric, or count — not a vague re-check condition).

**Handed to the senior-SWE script-feasibility pass (task #5):** items 2–4 above, which need
concrete file/interface/build-order design, not just a recommendation. Item 1 and the doc-only
items 5–6 are direct edits this session can make once the user confirms.

## 6. Build blueprint (mh:code-architect pass)

A senior-SWE design pass corrected and concretized §5 against the live codebase. Key corrections
to this doc's own recommendations, found by actually reading the repo rather than assuming a
greenfield build:

- **Item 2 already has a home: `scripts/_lib/weighted-score.py`** — not `rank.py`. It already
  accepts the exact criteria/weight/score/threshold shape Rule 14 describes. **Extend it with an
  opt-in `"perturb"` input field**, not a new sibling script — a new file would duplicate its
  fail-closed validation and violate `idea-audit/SKILL.md:282`'s explicit "one mechanism, not two"
  rule. The perturbation range is computed *exactly* via corner enumeration (the renormalized total
  is quasilinear in the weights, so extrema sit at the ±p box's vertices) — no PRNG, no seed,
  consistent with the repo's existing deterministic-script contract.
- **Byte-budget collision, must be sequenced correctly:** `docs/METHODOLOGY.md` is 3769/4096 bytes
  (327 headroom). §2's citation fix *shortens* line 34; §5 item 3's confidence-band wording
  *lengthens* it. **These must land as one commit**, not two independent edits that individually
  pass and jointly blow the cap.
- **Item 3 descoped**: confidence bands (`{level, reason}`) are real and cheap — `ideate-critic`
  already emits this shape, only `plan-reviewer.md:208`'s bare `0-100%` needs to change. The
  Brier-score idea from §5 does **not** fit coarse bands (Brier needs numeric probabilities) and
  was replaced with a markdown-only `docs/decision-log.md` (no script) gated behind a **20-row
  build trigger** for a future per-band hit-rate scorer, and a **5-row kill condition** if the log
  goes unused. This is the item's own "don't over-build a v1" guardrail, per its lowest ease score.
- **Item 4 schema comes from upstream, not invented here**: `mattpocock-skills`'
  `ADR-FORMAT.md` already specifies `status: proposed | accepted | deprecated | superseded by
  ADR-NNNN`. Dropped this doc's proposed `supersedes:`/`date:` keys — zero upstream support, zero
  current data. **ADR-0002 status is `deprecated`, not `superseded by`** — it was retired by
  deletion (v1.1.94), not by a successor ADR; a `superseded by ADR-NNNN` value would be false.
  Verified zero blast radius (nothing machine-reads `docs/adr/`); **no new harness-audit check**
  for 3 files — a `CLAUDE.md` convention clause instead, revisit at ~6 ADRs.

**Build order**: Item 4 first (fully independent) → §2 citation fix + Item 3a confidence-wording
as **one** commit (same line, opposite byte direction) → Item 2 (deep-audit's Final Verdict format
gains both the band wording and a fragility clause in the same pass) → Item 3b log last.

Full blueprint (exact code, file:line citations, test fixtures, risk list) is in this session's
record; the summary above is what changed from this doc's own §5 after checking it against the
live repo.

---

## References

Full per-claim citations live in the five source lanes this document synthesizes (opus-generated,
2026-09-19); the load-bearing ones are inlined above by author/year. Key sources, consolidated:

**MCDA / scoring:** Keeney & Raiffa (1976); Dawes (1979) *Am. Psychologist* 34(7):571-582; Grove et
al. (2000) *Psych. Assessment* 12(1):19-30; Saaty (1977, 1990); Belton & Gear (1983) *Omega*
11(3):228-230; Dyer (1990) *Mgmt Sci.* 36(3):249-258; Roy (1991) *Theory & Decision* 31(1):49-73;
Brans & Vincke (1985) *Mgmt Sci.* 31(6):647-656; Lahdelma, Hokkanen & Salminen (1998) *EJOR*
106(1):137-143.

**Anchored rubrics:** Smith & Kendall (1963) *J. Applied Psych.* 47(2):149-155; Landy & Farr (1980)
*Psych. Bulletin* 87(1):72-107; Jönsson & Svingby (2007) *Educ. Research Review* 2(2):130-144, DOI
10.1016/j.edurev.2007.05.002; Huynh et al. (2026) arXiv:2605.06283; Roy et al. (2026, PReMISE)
arXiv:2605.30803; Kim et al. (2023, Prometheus) arXiv:2310.08491.

**Behavioral:** Klein (2007) *HBR* 85(9):18-19; Mitchell, Russo & Pennington (1989) *J. Behavioral
Decision Making* 2(1):25-38; Veinott, Klein & Wiggins (2010) ISCRAM; Keysor, Wojtyna & Veinott
(2020) SJDM poster; Heath & Heath (2013) *Decisive*; Soll, Milkman & Payne (2015) *Wiley-Blackwell
Handbook of JDM* ch.33, DOI 10.1002/9781118468333.ch33; Arkes & Blumer (1985) *OBHDP* 35(1):124-140;
Stanovich & West (2000) *Behavioral & Brain Sciences* 23(5):645-665.

**Organizational:** Rogers & Blenko (2006) *HBR* Jan 2006; Bain & Company, "RAPID® Decision
Making"; Atlassian Blog (Russell, 2016), "DACI isn't something we invented"; Kurtz & Snowden (2003)
*IBM Systems Journal* 42(3):462-483; Snowden & Boone (2007) *HBR* Nov 2007; Boyd, "The Essence of
Winning and Losing" (1996 ed., 2012 Richards/Spinney PDF); Richards (2020) *Necesse* 5(1):142-165;
Bezos, 2015 and 2016 Letters to Shareholders.

**Software-eng:** Nygard (2011), cognitect.com/blog; adr.github.io; Kopp, Armbruster & Zimmermann
(2018, MADR) ZEUS 2018, CEUR-WS Vol-2072:55-62; Rust RFC book, github.com/rust-lang/rfcs; PEP 1
(Warsaw et al., 2000); Ubl (2020), "Design Docs at Google"; Southwick (1999) *High Noon*.

**LLM-judge:** Zheng et al. (2023) arXiv:2306.05685, NeurIPS 2023; Panickssery, Bowman & Feng
(2024) arXiv:2404.13076; Wataoka et al. (2024) arXiv:2410.21819; Verga et al. (2024) arXiv:2404.18796;
Xiong et al. (2023) arXiv:2306.13063, ICLR 2024; Tian et al. (2023) arXiv:2305.14975; Kadavath et
al. (2022) arXiv:2207.05221; Brier (1950) *Monthly Weather Review* 78(1):1-3.

**External validation:** docs.typesafe.ai/confidence, /patterns, /patterns/confidence-routing,
/patterns/composite-scoring, /concepts/system-one (fetched 2026-09-19).

**In-repo:** `docs/METHODOLOGY.md`, `docs/reference/operating-model.md`,
`docs/reference/haiku-decision-calls.md`, `docs/reference/spawn-brief.md`, `agents/plan-reviewer.md`,
`agents/ideate-critic.md`, `docs/adr/0001-0003`, `CHANGELOG.md` v1.1.99, auto-memory
`jev-typesafe-usecase-survey-2026-09-19.md`, `docs/research/jev-architecture-unmasked-archerhume-
2026-09-18.md`, `docs/research/haiku-jev-decision-primitive-2026-09-18.md`,
`docs/research/thinking-skills-frameworks-followup-research-2026-08-30.md`,
`llm-wiki/wiki/concepts/judgment-ladder.md`, `llm-wiki/raw/concepts/four-decision-biases-research.md`.
