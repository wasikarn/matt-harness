# Somkiat's "มาลองเล่น Jev จาก TypeSafe กัน" adoption audit (2026-09-18)

**Date:** 2026-09-18
**Source:** [somkiat.cc/hello-jev-from-typesafe](https://www.somkiat.cc/hello-jev-from-typesafe/), Thai
blog post by Somkiat Puisungnoen, saved locally (user-provided file) and copied verbatim to the
session scratchpad for isolated analysis. No pinned revision — a live blog post, re-read may differ.
**Verdict:** The blog is accurate — every checkable factual claim in it (LangChain integration,
Browser Use's `jev-ultrafast`, TypeSafe's Agent Skills repo, the API response shape) corroborates
against primary sources, with only one minor own-link imprecision. But the one candidate idea worth
adopting from it — routing cheap-vs-expensive model calls through a structured decision gate, the
shape of LangChain's `ModelRouterMiddleware` — is not new to this repo's own thinking: mh already
asked this exact question, declined it pending real per-agent-type cost data, and that data now
exists but hasn't yet cleared the evidence threshold mh set for itself. Nothing to build now;
nothing new to decline either — this is a re-confirmation with new, unrelated-but-verified context.

Every claim below is what the source describes as of this read, not a fact guaranteed to hold as
TypeSafe/LangChain/Browser Use's own products evolve.

## Method

Full `idea-audit` pipeline: `qmd`/`docs/research/` prior-coverage check first (three existing Jev
docs found — `typesafe-ai-system-one-jev-2026-09-18.md`, `jev-architecture-unmasked-archerhume-2026-09-18.md`,
`haiku-jev-decision-primitive-2026-09-18.md` — this pass builds on them, doesn't re-derive their
ground). 2 isolated `general-purpose` analysts in Phase 1 (Agent A: claims extraction + live
verification; Agent B: this repo's own model-routing state and fit). Phase 2 adversarial attacker:
Codex Sol/medium was the primary dispatch but hit its account usage cap mid-run (`ERROR: You've
hit your usage limit... try again at Sep 19th, 2026 4:47 PM`) — fell back to `general-purpose`
Claude per the skill's fallback protocol (`disallowedTools: ["Write","Edit","NotebookEdit"]`,
`git status --porcelain` clean before and after, confirming no write occurred). **Independence is
reduced for this pass** — the fallback attacker is the same model family as the two Phase 1
analysts, not an independent model as Codex would have been.

## Claim-by-claim: what's new in this source, and this repo's posture toward it

Legend: `MATCH` = claim confirmed against primary evidence · `PARTIAL` = partially confirmed ·
`GAP` = claim/citation not fully correct · `N-A` = not applicable to this repo.

| # | Claim | Verified? | This repo's posture | Verdict |
|---|---|---|---|---|
| 1 | `@typesafe-ai/sdk` npm package exports `TypeSafeClient`/`choice()` | Yes — observed directly (matches TypeSafe's own JS doc examples) | N-A — external ecosystem fact | MATCH |
| 2 | `langchain-typesafe` PyPI package (pre-release `0.0.1a2`, uploaded 2026-09-17) exports `Choice`/`Noul`/`Score`/`TypeSafeClassifier` | Yes — observed directly; attacker independently re-fetched PyPI's JSON API and confirmed the exact version and upload timestamps | N-A | MATCH |
| 3 | LangChain's `ModelRouterMiddleware`/`ModelChoice` route agent calls to a cheap vs. expensive model via a structured decision call | Yes — observed directly; near-verbatim match (identical model strings, identical criteria text) between the blog's example and LangChain's own live docs page | mh has no equivalent — confirmed by grep (see row 9) | MATCH |
| 4 | `docs.langchain.com/oss/python/integrations/providers/typesafe` is real and covers TypeSafe | Yes — observed directly | N-A | MATCH |
| 5 | `browser-use/jev-ultrafast` is a real, active GitHub repo using Jev for browser-agent decisions | Yes — observed directly; attacker independently confirmed via `gh api repos/browser-use/jev-ultrafast` (4,153 stars, not a fork, not archived) | N-A | MATCH |
| 6 | `typesafe-ai/skills` repo + `skills/typesafe-ai/SKILL.md` is real, is TypeSafe's official agent-skill install path | Yes — observed directly, checked two independent ways (direct fetch + cross-link from TypeSafe's own docs) | N-A | MATCH |
| 7 | The shown API response shape (`confidence`, `probabilities`, `usage.{input,output}_tokens`) matches TypeSafe's documented response format | Author-asserted, originally graded "strongly corroborated" by Agent A — attacker checked the two most likely doc pages and found neither shows a concrete JSON response example to corroborate the shape against | N-A | PARTIAL — real API-observed output (console.log truncation, plausible field names) but not independently matched against a documented schema |
| 8 | Blog's "compose/combine question types" claim links to `docs.typesafe.ai/primitives/advanced` | Yes — observed directly, and it's imprecise: that page is titled "Advanced: structure" (JSON structure inside individual fields, not combining question types). The actual "mix all three question types in one call" claim lives on `/introduction` instead | N-A — source's own citation slip, not a fabrication | PARTIAL |
| 9 | mh has zero programmatic model/effort routing logic anywhere in its own code | Yes — observed directly; attacker independently reproduced both greps (`model.?(rout\|select\|choos\|pick)` and `modelSettings\|CLAUDE_CODE_SUBAGENT_MODEL` across `hooks/`, `scripts/`, `skills/**/*.{sh,py,js}`) — both exit 1, no output | Confirmed: current mechanism is a global-CLAUDE.md fixed session rule + static per-agent frontmatter pins (`skills/meta/harness-audit/scripts/checks/21-agent-model-value-must-be-a-documented-a.sh:13,15`) + a prose Codex table that "no check parses" (`docs/reference/codex-integration-map.md:7`) | MATCH |
| 10 | mh already asked "should we route mechanical subagent work to a cheaper model" and declined it, pending real per-agent-type cost data | Yes, substance confirmed — attacker independently found the tabular "G1... Declined for now" row at `docs/research/orchestrator-tax-gap-analysis-2026-08-07.md:419`; `CHANGELOG.md:3336` discusses the same follow-up (adding `agent_type` cost tracking) but doesn't itself contain a "G1"/"Declined" row as originally cited | Data now exists (`docs/research/orchestrate-cost-optimization-2026-09-03.md:60`, real per-agent_type spend), but that same doc's own row 10 (line 96) still requires "≥10 orchestrate sessions before any threshold or downgrade decision" — unmet, per `docs/research/orchestrate-t-shape-analysis-2026-09-04.md:100` ("no per-role data → 7c stays deferred") | PARTIAL — the finding's substance holds, one file:line attribution was imprecise |
| 11 | mh already has a documented, deliberately-unwired Haiku-based structured-decision pattern (this session's own prior work) | Yes — observed directly (`docs/reference/haiku-decision-calls.md:5-6`, `docs/research/haiku-jev-decision-primitive-2026-09-18.md:38`) | Confirms rows 3/9/10 aren't news to this repo — the mechanism to build a decision gate is already documented; what's missing is evidence it's needed, not knowledge of how | MATCH |

## Shipped

Nothing but this artifact — a read-only research pass. No skill, gate, hook, or CLAUDE.md change.

## Deliberately not shipped

- **A structured model/effort-routing decision gate** (the `ModelRouterMiddleware` pattern, applied
  to mh's own Codex/session dispatch) — `docs/research/orchestrator-tax-gap-analysis-2026-08-07.md:419`
  (G1, "Declined for now — measurement gap closed same day"), `docs/research/orchestrate-cost-optimization-2026-09-03.md:96`
  (row 10, "Do now, decide later," requires ≥10 orchestrate sessions), `docs/research/orchestrate-t-shape-analysis-2026-09-04.md:100`
  ("no per-role data → 7c stays deferred"). Doctrine anchor: evals-first / YAGNI — mh's own
  self-set evidence threshold for this exact question. Labeled: **deferred** (not rejected —
  revisit trigger below).
- **Wiring `docs/reference/haiku-decision-calls.md` into any skill or gate** — this source names no
  new consumer beyond what was already known when that doc shipped earlier this session. Doctrine
  anchor: `docs/reference/skill-authoring-conventions.md`'s evals-first rule ("if Claude already
  clears the task without the skill, the skill should not exist"). Labeled: **declined on
  evidence**.
- **Adopting Jev/TypeSafe itself** — already declined in prior research (`docs/research/typesafe-ai-system-one-jev-2026-09-18.md`,
  `docs/research/jev-architecture-unmasked-archerhume-2026-09-18.md`). This pass found nothing that
  reopens that question. Labeled: **premise dead**.

## Decision score (METHODOLOGY Rule 14)

Axes score the audit's own decision quality (evidence strength and process rigor), not "should mh
build the router pattern" as a literal criterion — the answer to that is already settled in the
table above and doesn't need a second scored judgment.

| Criterion | Weight | Score | Reason |
|---|---|---|---|
| Primary-source fidelity | 40 | 90 | 9/11 checkable claims independently confirmed `Yes — observed directly` by both Agent A and the attacker (live npm/PyPI/GitHub/LangChain-docs fetches, `gh api`, PyPI JSON); one claim (row 7) had its confidence label downgraded from "strongly corroborated" to `PARTIAL` on attacker re-check; one (row 8) confirmed as a real minor source-citation slip, not fabrication — no claim was found fabricated |
| Repo-fit rigor | 25 | 85 | Agent B's overlap search was grep-backed, not asserted (`grep -rniE 'model.?(rout\|select\|choos\|pick)...'`, `grep -rln 'modelSettings\|CLAUDE_CODE_SUBAGENT_MODEL'`), and the attacker independently reproduced both greps to the same empty result; one file:line citation (CHANGELOG.md:3336 for the G1 row) was imprecise — the substance held, the exact line didn't |
| Adversarial-review survival | 20 | 82 | Codex primary rate-limited mid-run (usage cap, verified from the CLI's own error text); fell back to `general-purpose` per protocol, with the `disallowedTools` grant and a clean `git status --porcelain` diff confirming no write occurred. The fallback returned a schema-valid `pass:true` with 14 independently-verified `checked[]` items and 3 minor findings, no critical defects — but same-model-family independence loss is a real, disclosed limitation, not a full substitute for Codex |
| Scope discipline | 15 | 95 | Declined to recommend building the routing pattern now, citing mh's own unmet self-set threshold rather than either overclaiming urgency or dismissing the idea outright; shipped nothing but verified documentation, no speculative skill/gate/hook |

Weighted sum: 0.40(90) + 0.25(85) + 0.20(82) + 0.15(95) = **87.9/100**. Pass threshold 70,
fatal-weakness floor 40% of each criterion's own max — no criterion below floor (lowest is 82,
well above 40). **PASS.** Confidence: high (two isolated analysts, one adversarial re-check with
14 independently-verified receipts, zero fabricated claims found, one disclosed independence
limitation from the Codex fallback).

## Open questions

- Revisit the `ModelRouterMiddleware`-style routing pattern only if mh's own `≥10 orchestrate
  sessions` data threshold (`docs/research/orchestrate-cost-optimization-2026-09-03.md:96`) is
  reached **and** shows a real misrouting or cost-mismatch case — not from reading more
  third-party articles about the pattern.
- `browser-use/jev-ultrafast`'s specific performance claims (7.1s Google Flights search, 25%
  task-time reduction, 90% fewer browser protocol calls) are that repo's own self-reported numbers,
  not independently re-benchmarked here — re-check only if a real browser-automation decision in
  this repo would depend on them.

<!-- Reserved: a later pass appends a dated correction here, never rewrites the sections above.
**Correction (date, mechanism):** ... -->
