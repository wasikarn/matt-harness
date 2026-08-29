# "Claude models explained: choosing the best model for your use case" (Anthropic, Michael Segner) vs matt-harness

**Date:** 2026-08-29
**Source:** https://claude.com/blog/claude-models-explained-choosing-the-best-model-for-your-use-case
(local copy: `~/Downloads/Claude_models_explained__choosing_the_best_model_for_your_use_case.md`),
published 2026-07-24. No prior audit in this repo covers this specific article — qmd
(`mh-research`, `llm-wiki`, `mh-memory`) surfaces two adjacent-but-distinct prior audits instead:
`docs/research/tiered-multi-model-pipeline-audit-2026-08-21.md` (multi-tier plan/execute/review
pipelines — a different question, model *roles* not model *choice*) and
`docs/research/maximizing-value-claude-code-sessions-audit-2026-08-29.md` (published the same day
this audit runs, covers `/model`/`/effort` session mechanics — overlaps at the edges, not
duplicated below).

**Verdict: mostly confirms matt-harness's actual (not just documented) practice, one narrow but
real divergence in a shipped skill's default routing order, one benchmark citation that doesn't
hold up against its own linked primary source (live-verified, not just cache-disclosed), and one
concrete stale-doc fix worth a follow-up commit.** Read-only research pass — nothing in `skills/`,
`agents/`, `hooks/`, `docs/reference/**`, or `CLAUDE.md` was edited; every fix below is a named
candidate, not applied.

## Method

Read the article in full, cross-checked qmd for prior coverage, extracted every checkable claim
(model family membership, pricing, capability/benchmark claims, the advisor-strategy stat,
routing guidance), then verified each against (a) matt-harness's actual `agents/*.md` frontmatter,
skills, and docs on disk, and (b) the bundled `claude-api` skill's cached model/pricing/API
reference (`~/.../claude-api/SKILL.md`, cached 2026-06-24 — the best available ground truth in
this environment, itself one month older than the article) plus a live `firecrawl_scrape` of the
article's own linked source for the one specific benchmark number worth checking against its
primary source rather than trusting the article's restatement.

## Claim-by-claim

| # | Claim | Verified? | matt-harness posture | Verdict |
|---|---|---|---|---|
| 1 | Model family = Fable, Opus, Sonnet, Haiku; Mythos ships as Fable's dual-use twin (same underlying model, Project Glasswing only) | Yes — matches `claude-api` skill's cached table exactly (`claude-fable-5`, `claude-mythos-5` "Project Glasswing only", `claude-opus-5`/4.8/4.7/4.6, `claude-sonnet-5`/4.6, `claude-haiku-4-5`) | No family-membership doctrine of its own — matt-harness only ever names the current tier (Sonnet 5) it runs on | MATCH, no repo action needed |
| 2 | Mythos and Fable both require limited/30-day data retention | Yes — `claude-api` skill: "30-day data retention required — Claude Fable 5 is not available under zero data retention" | N/A — matt-harness has no data-retention policy surface | MATCH, out of scope |
| 3 | Sonnet = versatile everyday model, fits high-volume sub-agents in multi-agent orchestration | Yes, and matt-harness's actual fleet already lives this: 10 of 17 audited `agents/*.md` pin `model: sonnet`, 7 `opus`, 0 `haiku` (per `docs/research/maximizing-value-claude-code-sessions-audit-2026-08-29.md` Facet D) | Confirmed practiced, not just theoretical | **STRONG MATCH** — repo's own fleet composition is direct evidence for this claim, independent of the article |
| 4 | Haiku = lowest-cost/fastest tier for high-frequency workloads | Yes, pricing-wise ($1/$5 per MTok, cheapest in the `claude-api` table) | matt-harness tried this once and reverted: `agents/summarizer.md` was `model: haiku` (v0.68.395, commit `54242ac2`) then flipped back to `model: sonnet` a week later (v0.68.430, commit `c1df6891`) with the stated reason **"haiku lacks effort support"** | Pricing claim MATCH; the repo's own retune is a related aside, not primary evidence for claim 7 below — see the note there on why it's a different surface (fleet tiering, not the `cost-aware-llm-pipeline` skill) |
| 5 | Opus = reasoning-intensive enterprise tasks, ranks on GDPval-AA / Terminal-Bench 2.1 | Not independently checkable — no local benchmark data, and the article's own linked advisor-strategy source (see claim 10) cites "**Terminal-Bench 2.0**," not 2.1, for its own Opus-advisor runs | N/A | UNVERIFIED — plausible, minor version discrepancy noted but not a contradiction (benchmark suites do get point-released; not investigated further, out of scope for a repo-focused audit) |
| 6 | Default recommendation: **start with the most intelligent available model, use effort level to dial cost/quality** — because more capable models often take fewer turns, making cost-per-task lower despite higher price-per-token | Partially at odds with one of matt-harness's own shipped skills' *default entry point* — see "The real finding" below | `skills/patterns/cost-aware-llm-pipeline/SKILL.md` Best Practices bullet 1 says the opposite for the *starting* tier: *"Start with the cheapest model and only route to expensive models when complexity thresholds are met."* | **DIVERGENCE** at the entry-point decision, not a clean match — see below for the precise (not overstated) version of this finding |
| 7 | Effort level trades quality/speed/cost; a higher-class model at low effort can beat a smaller model — "sweep effort before routing to a cheaper model" | Yes — and the same skill file already states this rule twice more, not just once | `cost-aware-llm-pipeline`'s own Best Practices bullet **2** ("Sweep effort levels on the current model before routing to a cheaper one"), Anti-Patterns bullet 2 ("Routing to a smaller model before trying a lower effort level on the current one"), and Technique Map item 5 all state this — three places in one skill file agreeing with the article | **STRONG MATCH** in principle — but see below for why it can't actually be followed from the skill's own recommended starting point |
| 8 | "Combining models' strengths with the advisor strategy" — a cheap executor model calls a stronger advisor model to check its plan; cites **SWE-bench Pro: Sonnet 5 + Fable 5 advisor within 10% of Fable 5 solo, at 63% of Fable 5's full price** | The advisor tool/strategy itself is real and current (`claude-api` skill: "Advisor tool model pairing," `advisor_20260301`, pairing-validity rule); the **specific number does not match its own linked primary source, live-checked** — see below | Not implemented anywhere in matt-harness — zero hits for `advisor_20260301`/"advisor tool" in the repo. matt-harness's own `advisor()` tool (used constantly in this session) is a **different, same-named mechanism** — a Claude Code SDK-level "consult a stronger reviewer" call, not the Messages API server-side tool the article describes | Mechanism MATCH (real feature); **benchmark number UNVERIFIED/DISCREPANT** (see below); naming collision worth flagging |
| 9 | Evals/benchmarks guide model choice; benchmarks saturate on frontier models, so custom evals on real workloads are the tiebreaker | Yes | `skills/meta/eval-harness/SKILL.md` — an EDD (eval-driven development) framework skill already exists for exactly this, though per `docs/research/ai-native-sdlc-playbook-audit-2026-08-28.md` it's "prose-only... no CI job enforces it" | MATCH in doctrine, partial in enforcement — not this audit's finding, already recorded elsewhere |
| 10 | Mythos access-gated to "Project Glasswing" organizations | Yes — `claude-api` skill confirms verbatim | N/A | MATCH, out of scope |

## The real finding: the skill's default starting point forecloses its own escalation lever

Claim 6 isn't "the article contradicts the skill" in a simple sense — the skill isn't internally
random. It states the effort-first rule (claim 7) in three separate places: Best Practices
bullet 2, Anti-Patterns bullet 2, and Technique Map item 5. A single "start cheapest" bullet
sitting alongside three statements of "sweep effort before you downgrade the model" has an
obvious reconciling reading: "start cheapest" governs which tier you *enter* on, and effort-sweep
is what you do *within* a tier before escalating out of it. Those two ideas can coexist — most of
the time.

They stop coexisting at exactly the bottom rung. The skill's own Best Practices bullet 1 says
start on the cheapest model — which, per its own pricing framing and the `claude-api` table, is
Haiku. But Technique Map item 5 says, in the same file: *"Haiku models don't support \[effort\],
so it composes with routing only on the Sonnet/Opus branch."* So the recommended entry point is
the one tier where the article's central lever — dial effort before you downgrade the model —
isn't available at all. The skill's default starting position forecloses the very tool its own
escalation logic (and the article's) says to reach for first. That's a real, narrow,
evidence-backed divergence — not a blanket "the skill is wrong" claim, and not the same thing as a
self-contradiction.

*Aside, not corroborating evidence:* matt-harness's own `agents/summarizer.md` was moved off
Haiku specifically because "haiku lacks effort support" (commit `c1df6891`, v0.68.430) — a
fleet-tiering decision on a different surface (agent frontmatter, not the `cost-aware-llm-pipeline`
skill someone would load to build their *own* pipeline) that happens to run into the identical
constraint. Worth noting as color, not treated as proof the skill file itself is wrong — that's
argued directly above from the skill's own text.

**Candidate fix**, not applied (`skills/patterns/` is a runtime-loaded surface out of this
read-only pass's scope, and any edit needs a version bump anyway): add a caveat to Best Practices
bullet 1 — something like "...unless the cheapest tier can't take an effort dial (Haiku currently
can't), in which case start one tier up and sweep effort there first per item 5."

## The advisor-strategy stat doesn't survive a primary-source check

The article's specific claim — "on SWE-bench Pro Sonnet 5 with a Fable 5 advisor is within 10% of
Fable 5's score at 63% of the price of using Fable 5 for the whole task" — was checked directly
against the article's own linked source, `claude.com/blog/the-advisor-strategy`, via a raw
`firecrawl_scrape` (not a summarizing fetch — this repo has a standing lesson,
`webfetch-quote-not-primary-source-2026-08-20`, that a summarizing WebFetch call can fabricate or
truncate quoted claims, so a raw-content path was used deliberately) — fetched twice, once cached
(2026-08-28) and once forced live (`maxAge: 0`, fresh `scrapeId`, same session) to make sure "as
published" wasn't resting on a stale copy. Both fetches returned identical text. The page states
different benchmarks, different models, and different numbers entirely from the article's claim:

- **SWE-bench Multilingual** (not SWE-bench Pro): Sonnet 4.6 + Opus 4.6 advisor scored **+2.7
  percentage points** over Sonnet 4.6 solo, at **-11.9% cost per agentic task** (not "within 10%
  of the advisor model's score at 63% of its price").
- BrowseComp and Terminal-Bench 2.0 results are also reported, again for Sonnet 4.6 / Opus 4.6 —
  Haiku 4.5 + Opus 4.6 scored 41.2% on BrowseComp vs 19.7% solo, trailing Sonnet solo by 29% but
  costing 85% less.
- The code example on the page pins `model: "claude-sonnet-4-6"` (executor) and
  `"model": "claude-opus-4-6"` (advisor) — Sonnet 5 / Fable 5 do not appear anywhere on the page.

**This does not mean the article's number is fabricated** — Anthropic runs continuous internal
evals and could well have a newer SWE-bench Pro result for Sonnet 5 + Fable 5 that simply isn't
on this specific blog post (which is dated April 9, 2026 on-page, three and a half months before
the article). But as published, the article's own cited link does not corroborate its own
quoted number, benchmark, or model pair. Worth flagging precisely rather than either repeating the
number uncritically or asserting it's wrong — say what was checked and what it found, nothing more.

## What was adopted / shipped

Nothing — this was a read-only research pass by design (task scope explicitly excludes editing
`skills/`, `agents/`, `docs/reference/**`, or `CLAUDE.md` to avoid colliding with a second agent
auditing a different article in the same working tree). Every actionable item below is named as a
candidate, not applied.

## What was deliberately not done (candidates for a follow-up commit)

1. **Close the routing-order gap in `skills/patterns/cost-aware-llm-pipeline/SKILL.md`.**
   Best Practices bullet 1 ("start with the cheapest model") recommends entering on Haiku, the one
   tier where the file's own item 5 says the effort dial doesn't exist — so the recommended entry
   point forecloses the skill's own first-choice lever (also stated in Best Practices bullet 2 and
   Anti-Patterns bullet 2) before it can ever be used. Exact fix: append a clause to bullet 1 —
   "...unless the cheapest tier has no effort dial (Haiku currently doesn't), in which case start
   one tier up and sweep effort there first." Highest-value candidate in this audit — a real,
   narrow, textually-verified gap in a shipped skill's default sequencing, not a missing
   nice-to-have.
2. **Update the stale example in `docs/reference/env-vars.md` line 63.** The `CLAUDE_CODE_SUBAGENT_MODEL`
   row's parenthetical — *"kbg pins per-agent models (e.g. `agents/summarizer.md` → `haiku`,
   v0.68.395)"* — describes a state that was reverted one version later (`c1df6891`, v0.68.430,
   `summarizer.md` → `sonnet`, "haiku lacks effort support"). The doc line is now factually wrong
   about the one example it names. Exact fix: swap the example for a currently-true one (e.g. cite
   the current opus/sonnet split directly, or just say "see `agents/*.md` frontmatter" without a
   specific stale example).
3. **Cross-reference the article's own linked companion post** ("Choosing a Claude model and
   effort level in Claude Code," `claude.com/blog/claude-model-and-effort-level-in-claude-code")
   in `docs/reference/env-vars.md`'s existing `/model`/`/effort` section — that section already
   covers the same ground (model-switching, effort stickiness, cache-key interaction) but doesn't
   cite this specific companion doc, unlike the neighboring citations to `commands.md` and
   `prompt-caching.md` in the same section. Low-value, pure completeness — not urgent.
4. **Name the advisor-tool / `advisor()` naming collision somewhere discoverable**, if it's ever
   likely to cause confusion — e.g. a one-line note in `docs/reference/reasoning-models.md` or
   wherever `advisor()` is documented, clarifying it's a Claude Code SDK-level tool distinct from
   the Anthropic Messages API's server-side `advisor_20260301` tool the article describes. Purely
   a documentation-clarity nice-to-have; no functional gap, no observed confusion incident (Rule 2
   — not worth building blind).

None of these touch `agents/*.md` model tiers themselves — the article gives no evidence that any
current pin (10 sonnet / 7 opus / 0 haiku) is wrong for its job; that's a separate question this
audit didn't investigate.

## Sources

- Article: https://claude.com/blog/claude-models-explained-choosing-the-best-model-for-your-use-case
  (Michael Segner, 2026-07-24; local copy `~/Downloads/Claude_models_explained__choosing_the_best_model_for_your_use_case.md`)
- Advisor strategy (fetched live via `firecrawl_scrape`, cache hit 2026-08-28):
  https://claude.com/blog/the-advisor-strategy
- `claude-api` skill's cached model/pricing/API reference (cached 2026-06-24), bundled with this
  session
- Repo evidence: `agents/summarizer.md` + its git history (`54242ac2`, `c1df6891`),
  `skills/patterns/cost-aware-llm-pipeline/SKILL.md`, `docs/reference/env-vars.md`,
  `docs/skill-authoring-conventions.md`
- Prior related audits (qmd): `docs/research/tiered-multi-model-pipeline-audit-2026-08-21.md`,
  `docs/research/maximizing-value-claude-code-sessions-audit-2026-08-29.md`
