# Thinking skills / thinking frameworks — follow-up research (2026-08-30)

Follow-up to the same day's thinking-skill-cue-routine article audit (memory:
`thinking-skill-cue-routine-article-audit-2026-08-30`). That audit checked the
article's applicability to matt-harness's own doctrine and shipped two changes.
This is separate, broader research: (1) does matt-harness's existing 39-model
reasoning catalog (`docs/reference/reasoning-models.md`) have real gaps, and
(2) does the article's own uncited claims — and the two claims *this session*
made about it without checking — actually hold up against primary literature.

3 parallel forks, each required to check `qmd` (mh-research/mh-memory/llm-wiki)
before external search, and to cite primary sources, not summaries.

## 1. Catalog gap check

`grep -in "mece\|pyramid principle\|issue tree\|hypothesis-driven\|minto"` and
`grep -in "competing hypotheses\|heuer\|key assumptions check\|structured
analytic"` against `docs/reference/reasoning-models.md`'s full 39-row table plus
the kbg-native-scaffolds table both return zero hits. Confirmed by hand as a
second pass, not just grep.

`llm-wiki` has a page on SCQA/Minto Pyramid Principle
(`wiki/concepts/scqa-minto-pyramid.md`), but it's scoped to Minto's
*communication-structuring* method, not MECE-the-decomposition-technique — both
are Minto's work but conceptually distinct; the existing page doesn't cover the
gap. No hits anywhere in this repo's qmd collections for ACH/Heuer/Key
Assumptions Check — genuinely uncovered ground.

**3 candidate additions, all pass the non-overlap test against the existing 39
rows:**

| Candidate | Origin (primary source) | One-line | Why it's non-overlapping |
|---|---|---|---|
| **MECE** | Barbara Minto, McKinsey, developed 1963-73, published in *The Pyramid Principle: Logic in Writing and Thinking* (Minto traces the underlying idea to Aristotle) | Partition a problem into categories that don't overlap and leave nothing out, before analyzing any of them | No existing row checks partition-completeness of a problem space — `systems-thinking` maps relationships, `first-principles` probes depth, neither checks exhaustiveness/double-counting |
| **Analysis of Competing Hypotheses (ACH)** | Richards J. Heuer Jr. (CIA, 45-year veteran), Ch. 8 of *Psychology of Intelligence Analysis* (CIA Center for the Study of Intelligence, 1999) | Build a matrix of every plausible hypothesis against every piece of evidence, then hunt for evidence that *disconfirms* each — not evidence that confirms the leading one | `red-team` is adversarial roleplay against one position; `bayesian`/`probabilistic` update likelihoods without a structured multi-hypothesis matrix; `steel-manning` evaluates two sides, not N. Closest decades-field-tested real-world analog to the article's own "what evidence would change our conclusion?" question |
| **Key Assumptions Check** | Same Heuer/Pherson tradecraft family — a distinct sibling technique to ACH, not a rename | Systematically list *every* assumption underlying the current analytic line and stress-test each one | matt-harness's own METHODOLOGY Rule 1 asks for the *one* riskiest assumption; this is a more exhaustive, checklist-driven procedure, not a single-name lens |

No anchoring proposed for any of the three — this repo's own settled precedent
(`analytical-thinking-article-kbg-audit-2026-08-19`) blocks anchoring a
vendored model into a kbg surface on the strength of an article resonating.
These are catalog-documentation gaps only, matching the existing convention
where most of the 39 rows are already "considered, no anchor."

## 2. Debiasing-training and checklist-effectiveness claims

The article claimed (uncited): (a) knowing a framework doesn't mean people
apply it under pressure, (b) simple routines beat complex frameworks under
pressure. This session's implementation work leaned on both without checking
either.

**Claim (a) — confirmed, more specific than the article states.**
- Soll, Milkman & Payne (2015), "A User's Guide to Debiasing," *Wiley-Blackwell
  Handbook of Judgment and Decision Making* (DOI 10.1002/9781118468333.ch33) —
  splits debiasing into person-focused vs. environment-focused strategies,
  directly backing the article's System-Design framing.
- A 2021 Frontiers systematic review (PMC8397507) found insufficient evidence
  that bias-mitigation interventions substantially help real-life decisions,
  and that abstract knowledge alone doesn't transfer.
- Morewedge et al. (2015, *Policy Insights BBS*) found a single play of a
  purpose-built serious game measurably reduced confirmation bias, bias blind
  spot, and correspondence bias, with effects still measurable weeks to months
  later. Its field-validated follow-up, Sellier, Scopelliti & Morewedge (2019,
  *Psychological Science*, "Debiasing Training Improves Decision Making in the
  Field," corrigendum at PubMed 32423341), found trained graduate students
  were 19% less likely to choose the inferior, bias-confirming option in an
  unannounced real business-case exercise modeled on the Challenger launch
  decision — but only from *engaging, repeated, feedback-driven* training (the
  same serious game), never passive lectures. (Verified directly against
  primary-source search results 2026-08-30, not just the doc's own earlier
  paraphrase — the original draft blended a 19-29% range and a "2-3-month"
  figure across both papers without attributing which came from which; only
  the 19% Sellier figure could be pinned down with confidence, so the
  Morewedge-specific number is described qualitatively instead of guessed.)
- Net: the literature's own split maps almost exactly onto the article's
  Knowledge vs. Cue/Routine/Repetition/Feedback distinction — passive
  knowledge fails to transfer, practiced/reinforced routines do.

**Claim (b) — confirmed, with a finding that reinforces the article's other
thesis one level deeper.**
- Haynes et al. (2009, *NEJM*), WHO Surgical Safety Checklist, 8 hospitals —
  real, foundational, genuine mortality/complication reduction.
- Urbach et al. (2014, *NEJM*), Ontario's mandatory rollout across 101
  hospitals (~215,000 procedures) — **no significant reduction** in mortality.
  The field's own explanation: implementation fidelity — the checklist only
  works with genuine team engagement, not mechanical box-ticking under
  time/social pressure.
- This independently reproduces the article's own "System Design, not just
  Training" argument: even its favored intervention (a simple checklist) fails
  exactly the way the article predicts, when the surrounding culture doesn't
  support genuine use.

**Side finding, flagged not fixed**: `llm-wiki` cites "Bornioli, Lewis, Bryan
2019, Effectiveness of Debiasing, PubMed 31414559" with `verification: partial`,
`verified_count=0` already marked in its own frontmatter. That PubMed ID
resolves to an unrelated cardiology paper; no such debiasing paper was found
anywhere. Likely fabricated or badly misattributed. Out of scope to fix here —
`llm-wiki` writes are operator-gated per this repo's own CLAUDE.md
(`raw/` never edited by an assistant; `/mh:wiki-ingest` is the gated path) —
flagging for the operator to correct via their own vault workflow.

## 3. This session's own uncited claims, checked

**Habit-formation formula** — the article's "Usable Thinking Skill = Knowledge
+ Cue + Routine + Repetition + Feedback + Supportive Context" was described
earlier this session as mirroring "BJ Fogg's Behavior Model... cue-routine-
reward loop from Duhigg's 'The Power of Habit'" — that claim was pattern-matched
from general knowledge, not checked at the time. Verified now: both cited
models are real (Fogg's B=MAP, Stanford 2009 / *Tiny Habits* 2019; Wood & Neal,
*Habits — A Repeat Performance*, 2006, and *A New Look at Habits and the
Habit–Goal Interface*, 2007, *Psychological Review*) — but the article's
formula is a loose restatement, not grounded in either directly, and
conflates a real tension between the two: Fogg's model is a *deliberate*
prompt triggering a *conscious* action; Wood & Neal's finding is the opposite —
real habits are triggered automatically by context cues, largely *unaffected*
by conscious intent. The article's "Cue" and "Routine" bundle both mechanisms
without distinguishing them. Directionally right, imprecise in the specifics.
This claim was never written into a committed file or memory — conversational
only, no durable correction needed.

**Hindsight-bias citation and fix** (the post-mortem `## 10. Assumption Trace`
caution added this session) — Fischhoff, B. (1975), "Hindsight ≠ foresight:
The effect of outcome knowledge on judgment under uncertainty," *Journal of
Experimental Psychology: Human Perception and Performance*, 1(3), 288–299:
real, correctly attributed. Slovic & Fischhoff (1977), *On the psychology of
experimental surprises*, same journal, is also real — but its own
"consider-the-opposite" debiasing instruction **did not reliably work**: a
2025 review ("Fifty Years of Hindsight Bias Research") found this style of
after-the-fact debiasing only partially attenuates the bias and can overcorrect
into the opposite direction. The stronger, better-evidenced technique —
recording the belief *before* the outcome is known, so it cannot later be
distorted — is exactly what the shipped fix already implements (anchor to a
contemporaneous artifact, or state explicitly none exists). This also matches
Tetlock's *Superforecasting* calibration methodology, independently confirmed
in this repo's own `llm-wiki/raw/concepts/four-decision-biases-research.md`.
**The shipped fix is the stronger of the two real techniques, not the weaker
one — no follow-up change needed.**

## Bottom line

Nothing here changes what was already built and shipped this session — the
post-mortem fix holds up as the field's actual best practice, and the article's
core claims are, on net, better-supported by real research than the article
itself argues (uncited but directionally correct, in some places more
specific than it states). The one concrete action worth taking: add the 3
catalog rows above (MECE, ACH, Key Assumptions Check) to
`docs/reference/reasoning-models.md` as documentation-only "considered, no
anchor" entries — a real, evidenced gap in a catalog that claims to be
"unified," not a build/anchor decision.
