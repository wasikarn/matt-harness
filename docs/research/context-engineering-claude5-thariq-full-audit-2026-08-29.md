# "The new rules of context engineering for Claude 5 generation models" (Thariq, Anthropic) vs matt-harness — full claim-by-claim pass

**Date:** 2026-08-29. Author: Thariq Shihipar (member of technical staff, Anthropic Claude Code
team). Published 2026-07-24. Source file: `~/Downloads/The_new_rules_of_context_engineering_for_Claude_5_generation_models.md`.
Repo state checked against: matt-harness v0.68.544 (`.claude-plugin/plugin.json`).

## Relationship to prior coverage — read this first

`docs/research/prompt-cut-80-cherny-2026-08-09.md` already audited this same article once, but
only as a **delta pass**: it cross-referenced the article against a separate Boris Cherny talk and
extracted 4 "Thariq-only claims" beyond what the talk covered. Three of those led to real adoptions
in `docs/harness-decay-cadence.md` (v0.68.238):

1. Product-consistency carve-out (output-styles / templated bodies aren't decay-eligible on "the
   model got smarter" grounds).
2. Scored measure + eval-lifespan asymmetry ("quality holds" must be a score, not a recollection;
   eval sets accumulate and retire on saturation, unlike the rules they measure).
3. `/doctor` named as a candidate-surfacing lens in the decay cadence.

**These 3 are settled — not re-litigated here.** This pass is the first **full** read of the
article end to end (all six then/now flips, the "applying this to your context" section, and the
closing "try simplifying" section), re-verified against the CURRENT repo (moved on from v0.68.238
to v0.68.544 since the prior pass — 306 versions). Two of the prior pass's remaining rows —
"tool-examples-constrain" and "conflicting instructions across assembled context," both left as
"— noted, no change" in 2026-08-09 — are re-verified fresh here rather than carried forward, per
Rule 2 (a "no incident yet" verdict is time-stamped, not permanent).

## Method

Read the article in full. Checked qmd (`mh-research`, `llm-wiki`, `mh-memory` collections) for
prior coverage of each theme before treating anything as novel — a curated wiki summary of this
exact article already exists (`llm-wiki/wiki/ai-agents/knowledge-context/context-engineering-claude-5.md`),
and a separate, thorough audit of the article's auto-memory claim already exists
(`docs/research/agent-memory-engineering-2026-08-07.md`). Neither is matt-harness's own doctrine —
both are prior research notes — so their existence narrows what's genuinely unaudited rather than
closing the loop by itself. Verified every remaining claim against the live repo: `CLAUDE.md`,
`docs/METHODOLOGY.md`, `docs/reference/operating-model.md`, `docs/harness-decay-cadence.md`,
`docs/skill-authoring-conventions.md`, `skills/meta/harness-audit/scripts/checks/*.sh`, and grep
across `skills/`/`hooks/`.

## Headline verdict

matt-harness independently arrived at most of this article's architecture before reading it —
consistent with the prior partial audit's framing ("external validation of the decay doctrine at
the vendor layer"). One genuine, evidenced gap surfaced this pass that the 2026-08-09 audit had
provisionally cleared: the article's "conflicting instructions across assembled context" failure
mode, parked then as "no incident yet," now has a dated, in-repo, post-2026-08-09 incident proving
it — this repo shipped a factually wrong claim in `CLAUDE.md` itself that directly contradicted
another section of the same file (`CLAUDE.md:364`, caught 2026-08-26,
`MEMORY.md`'s `claude-md-mechanism-claims-are-claims-2026-08-26` entry). Nothing in the repo
detects that class of defect automatically. Named as one candidate below, not built (read-only
pass, per the dispatch instructions).

## Claims, verification, and mapping

Verdicts: **✓ already doctrine/mechanism** · **✓(session)** = observed directly in this session ·
**Δ already adopted (2026-08-09)** · **Gap** = evidenced, not built · **— adjacent, no change** ·
**N/A** = doesn't apply to a Claude Code plugin repo

| # | Claim (article section) | Verified? | matt-harness posture | Verdict |
|---|---|---|---|---|
| 1 | Give-rules → let-Claude-use-judgment: older models needed prescriptive constraints (e.g. a hard no-comments rule) that cost more in conflict-resolution than they save on Claude 5; the new system prompt collapses to one judgment-based sentence | Author-asserted (Anthropic-internal system-prompt diff); not independently checkable from outside | `docs/harness-decay-cadence.md`'s "Hard guard" already draws the exact line this claim needs: safety/worst-case-scenario rules (destructive Bash, hardcoded paths, verifier tampering) stay hard `deny` gates regardless of model generation, while everything else is decay-eligible on disable-and-measure. `CLAUDE.md`'s own git-hygiene rules (never `rm -rf`, never `git add -A`, never `--no-verify`) are exactly the worst-case-scenario class the article says survives every cut (claim 7 in the prior Cherny audit) — matt-harness didn't just avoid over-constraining, it already has the taxonomy to tell which prescriptive rules should stay | ✓ already doctrine |
| 2 | Give-examples → design-interfaces: tool examples constrain exploration; instead design expressive parameters (Todo tool's `pending`/`in_progress`/`completed` enum teaches usage without an example) | Author-asserted for Claude Code's own Todo tool; general principle plausible and independently stated elsewhere (llm-wiki's own `context-engineering-principles.md`: "descriptive params (`user_id` not `user`)") | matt-harness doesn't define new Claude Code tools, so the literal claim doesn't transfer 1:1 — but the analogous surface (skill/agent frontmatter) already leans structured-interface over prose-example: `effort:` tiers (low/medium/high/xhigh), `model_limitation:` field, `disable-model-invocation` flag are all typed, enum-shaped fields the model reads to infer behavior, not worked examples embedded in every skill body. Independently arrived at, not sourced from this doctrine | — adjacent, no change |
| 3 | Put-it-upfront → progressive-disclosure: verification/code-review moved out of the system prompt into separately-callable skills; some tools are "deferred loading" (agent must `ToolSearch` before the full definition loads); the same applies to CLAUDE.md/SKILL.md — a tree of files loaded when needed, not one central repository | **Yes — observed directly this session.** This exact audit task loaded `mcp__plugin_qmd_qmd__query`'s full schema via `ToolSearch` mid-session (it was listed by name only until then); the native skill listing carries separately-invocable `security-review`, `simplify`, `init` alongside matt-harness's own `mh:code-review`(via mattpocock)/`mh:security-auditor` — verification and review are call-on-demand skills, not baked into every session's fixed prompt | matt-harness's own `context-budget/SKILL.md` already documents the deferred-tool-loading mechanism explicitly, confirmed against official docs 2026-07-31 (`docs/research/official-docs-audit-2026-07-31.md`): "MCP tool schema: deferred by default... only tool names + server instructions load at session start; full schemas load on demand." The skill/agent fleet is itself a tree (`skills/<bucket>/<name>/SKILL.md`, `references/*.md` for progressive disclosure inside a skill, `docs/reference/**` loaded only when named) rather than one CLAUDE.md — and CLAUDE.md explicitly delegates ("load only when actually authoring... `docs/skill-authoring-conventions.md`"). Prior audit's 4th Thariq-only claim already called this "kbg already runs this shape" — reconfirmed, stronger evidence this pass | ✓(session), Δ reconfirmed |
| 4 | Repeat-yourself → simple-tool-descriptions: older models needed instructions repeated in both the system prompt and the tool description; Claude 5 doesn't — delete the duplicate, put usage guidance in the tool description | Author-asserted (Anthropic-internal prompt diff) | No mechanism in matt-harness checks for duplicated or *contradicted* instructions across assembled surfaces (CLAUDE.md vs. a skill body vs. another section of CLAUDE.md itself). `harness-audit` check 43 is a **budget** check (cumulative description char count vs. the platform's skill-listing ceiling), not a duplication or consistency check — confirmed by reading the check's own header comment. This is the same absent mechanism claim 13 below needs; one candidate, not two (see below) | Gap (shared with #13) |
| 5 | Memory-in-CLAUDE.md → auto-memory: stop telling users to write memory via `#`; Claude now auto-saves relevant memories | **Yes — this session's own context.** The `MEMORY.md` index injected into this session is explicitly the auto-memory mechanism the article describes | Already the subject of a dedicated, thorough prior audit — `docs/research/agent-memory-engineering-2026-08-07.md` — not re-litigated here. That doc's own finding stands: native auto-memory (`autoMemoryEnabled`) is the primary writer, matt-harness's `memory-lint.py` + `mh:learn` are a governance layer on top (dangling-link/orphan/index-drift detection, retrospective cross-turn sweep), not a competing memory mechanism. No new finding this pass | Δ already audited (2026-08-07) |
| 6 | Simple-specs → rich-references: Claude 5 can use HTML artifacts, code-shaped specs (a detailed test suite, or a function in another codebase to port), and rubrics (verifier agents checking taste via dynamic workflows) as references, not just markdown plan files | Author-asserted, plausible and consistent with Anthropic's own Artifacts/dynamic-workflows launches (both linked from the article) | Three separate matches already present, independently arrived at: (a) **code-shaped specs** — `mattpocock-skills:tdd` and `METHODOLOGY.md` Rule 4's "failing test first" convention already treat a test as the spec, not a description of one; `mh:spec-miner` extracts Requirement/Invariant blocks directly from code for brownfield onboarding. (b) **HTML artifacts as references** — `plannotator-effective-html`, `design`, `dataviz`, `artifact-design` are all installed and routed to via the Composer-not-creator doctrine before building anything native; matt-harness itself doesn't build UI, so it has no reason to build its own version. (c) **Rubrics + verifier agents** — `mh:score-decision` (stated criteria + weights + numeric result + pass/fail) is the rubric primitive, and the maker≠checker architecture (fresh-context reviewer/verifier agents: `mh:plan-reviewer`, `mh:blind-spot-hunter`, `mh:security-reviewer`, etc.) is exactly "spin up a verifier agent against a rubric," independently derived from the verifier-separation crux (`docs/reference/operating-model.md`), not from this article. **Do not build a new "rubric primitive"** — the ground is already held; this is vocabulary matching an existing mechanism, not a missing one | ✓ already doctrine, no build |
| 7 | System Prompt layer: heavily product-tied; a Claude Code user won't touch it, but a custom-harness builder should spend real time there | N/A framing check | matt-harness is a Claude Code **plugin**, not a from-scratch agent harness with its own system prompt — this layer genuinely doesn't apply. CLAUDE.md is the closest analog matt-harness controls, covered under claim 8 | N/A |
| 8 | CLAUDE.md layer: keep it lightweight, briefly describe the repo's purpose, spend most tokens on codebase-specific gotchas, avoid stating what Claude can infer from the filesystem; use progressive disclosure into skills for long verification instructions | Author-asserted general guidance | This is a **content-ratio** claim, not a line-count claim — checked accordingly rather than against `wc -l` alone. Root `CLAUDE.md` is 489 lines / 4,630 words. Read end to end: it is overwhelmingly incident-derived, project-specific gotcha content (the entire "Non-obvious gotchas" section, the git-hooks relative-path incident, the plugin-cache staleness trilogy, the concurrent-sessions discipline) — not restated obvious-from-the-filesystem facts. It already delegates the long stuff out: skill-authoring conventions moved to `docs/skill-authoring-conventions.md` ("load this when actually authoring... none of it is needed for routine work"), agent-tool-patterns to its own file, decision-doctrine mapping to `docs/reference/decision-doctrine-map.md`. On its own terms, CLAUDE.md conforms — its size is a consequence of following the advice (a public plugin repo with more incident history than most single-project CLAUDE.md files), not a violation of it. Separate, smaller fact: no `harness-audit` check measures CLAUDE.md's own byte/token size the way `compress-docs`'s 20K threshold covers other docs — `compress-docs/SKILL.md` explicitly excludes "grading a CLAUDE.md's content completeness or currency." Not proposing a trim here — the decay cadence's own "score, not feel" rule would require a concrete measure before any cut, and none exists today | ✓ conforms (content-ratio), instrument-gap noted only |
| 9 | Skills layer: lightweight guides, don't over-constrain except in highly important areas, use progressive disclosure for long skills (split into many files), best skills encode team/product-specific opinions | Author-asserted general guidance | Matches matt-harness's shipped conventions closely, independently sourced from matt-pocock's own `writing-for-agents` doctrine (`docs/skill-authoring-conventions.md`): leading words, one trigger per branch, no-op test as the "don't over-constrain" backstop, progressive disclosure explicitly named as one of the doctrine's "two loads" (context load vs. cognitive load). Mechanically enforced, not just prose: pre-commit's new-file LOC gate hard-blocks a new `SKILL.md` over 200 lines (`MH_SKIP_LOC_GATE=1` escape hatch), and the 10 largest live skills all sit exactly at the 200-line ceiling (`production-audit`, `review-fixtures`, `pr`, `recursive-improve`, `ideate`) — the cap is real, not aspirational. "Team/product-specific opinions" matches the fleet's whole premise (a Matt-Pocock-first, kbg-native doctrine layer) | ✓ already doctrine, mechanically enforced |
| 10 | References layer: `@`-mention files as references; prefer files in code over descriptions — an HTML mockup beats a description or screenshot | Author-asserted general guidance | Same finding as claim 6(b): matt-harness routes to `plannotator-effective-html`/`design`/`dataviz` before building UI natively, and its own review/spec surfaces already prefer code-shaped references (a test, a diff, a file:line citation) over prose description — `METHODOLOGY.md` Rule 4's "Dispatched-agent claims need one checkable fact" makes this an explicit requirement: a subagent's prose claim isn't accepted without a file/line/command-output citation | ✓ already doctrine |
| 11 | Try simplifying / `claude doctor`: Anthropic shipped `/doctor` explicitly to help rightsize skills and CLAUDE.md files; points to the Fable field guide for prompting more advanced models | Already verified 2026-08-09 (`/doctor` is the in-session command, not the CLI's install-health-only `claude doctor`) | Already adopted into `docs/harness-decay-cadence.md`'s Cadence step 1 as a candidate-surfacing lens (v0.68.238) — not re-litigated | Δ already adopted (2026-08-09) |
| 12 | Fable field guide pointer — companion article on prompting more advanced/agentic models | Not independently re-checked this pass (out of scope: this is a pointer to a different article, not a claim about matt-harness) | `plugin.json`'s own description already names Fable specifically ("Fable plan, Sonnet execute, Opus review" — `skills/meta/tiered-pipeline`), so matt-harness already treats Fable as a distinct tier with its own role, consistent with the article's framing that Fable needs different handling than Sonnet/Opus. No new finding | — adjacent, no change |
| 13 | ("Unhobbling" section) Conflicting instructions across assembled context — e.g. "leave documentation as appropriate" colliding with "DO NOT add comments" in the same request — is Claude 5's real failure mode when constraints aren't unified; older models needed every constraint spelled out, Claude 5 has to reconcile competing signals instead | **Re-verified this pass, verdict flipped from 2026-08-09.** The prior audit parked this as "— noted... no incident has proven the need." A dated, in-repo incident now exists, post-dating that verdict: `CLAUDE.md:364` (the Cache-invalidation bullet) reads "...that was wrong, and it contradicted the Architecture note one section up" — a factually incorrect mechanism claim shipped into CLAUDE.md that directly contradicted a different section of the *same file*, undetected until a manual sweep on 2026-08-26 (`MEMORY.md`'s `claude-md-mechanism-claims-are-claims-2026-08-26` entry: "'X cats Y from the cache' was false and contradicted another section of the same file"). This is Thariq's failure mode one level up: not two *instructions* in tension, but two *factual claims* in the same assembled document in tension — same root cause (nothing cross-checks internal consistency of what gets assembled into context), same detection gap | **Gap — evidenced, not built.** No shell check or hook in `skills/meta/harness-audit/scripts/checks/` looks for cross-section or cross-surface contradiction; harness-audit check 26 checks `@import` resolution (files exist), not content consistency. This is the shared mechanism claim 4 also needs |

## What was adopted / shipped this pass

Nothing — this is a read-only research pass per the dispatch instructions (no runtime-loaded file
may be edited by this agent; a second agent may be working the same tree in parallel).

## What was deliberately not done

- **No cross-surface/cross-section consistency checker built.** This is the one genuine, evidenced
  gap (claims 4 and 13 above share it). **Candidate, precisely scoped:** a new `harness-audit`
  check (next free number after the current highest) that flags, at minimum, self-contradiction
  within a single file — e.g. a claim that a mechanism X does Y, checked against the file's own
  other sections making a conflicting claim about X. A general-purpose semantic-contradiction
  detector is out of reach deterministically (same reasoning `docs/harness-decay-cadence.md`'s
  "Refused extension" section already used to decline a runtime reasoning-verifier); a narrower,
  file-scoped grep-for-known-contradiction-shapes check (e.g., "cats X from the cache" appearing
  near a sentence asserting the opposite) is the buildable slice, closer to what `memory-lint.py`'s
  pattern-cluster mode already does for the memory store. Not proposed for cross-*file* consistency
  (open-ended, no bounded grep target) — only within a single file, where the 2026-08-26 incident
  actually occurred. Left as a candidate per the dispatch instructions, not built.
- **No CLAUDE.md trim.** Claim 8 found CLAUDE.md conforms to the article's content-ratio advice on
  read; proposing a cut without a "score, not feel" measure would violate the decay cadence's own
  rule. The absent CLAUDE.md-size instrument is named as a fact, not a recommendation to add one —
  no incident has shown it's needed yet (Rule 2).
- **No new rubric-primitive or verifier-agent-on-taste mechanism.** Claim 6(c) found `score-decision`
  plus the existing maker≠checker verifier-agent fleet already hold this ground. Building a second,
  parallel "rubric" concept would be redundant scaffolding, not a gap.
- **No re-litigation of the 3 already-adopted deltas** (product-consistency carve-out, scored
  measure + eval-lifespan asymmetry, `/doctor` lens) or the auto-memory claim (separately, fully
  audited in `docs/research/agent-memory-engineering-2026-08-07.md`).

## Sources

- Thariq Shihipar (@trq212), "The new rules of context engineering for Claude 5 generation models,"
  claude.com/blog, 2026-07-24. Local copy: `~/Downloads/The_new_rules_of_context_engineering_for_Claude_5_generation_models.md`.
- `docs/research/prompt-cut-80-cherny-2026-08-09.md` (prior partial audit — Cherny-talk cross-reference
  + 4 Thariq-only deltas).
- `docs/research/agent-memory-engineering-2026-08-07.md` (auto-memory, fully audited separately).
- `llm-wiki/wiki/ai-agents/knowledge-context/context-engineering-claude-5.md` (curated wiki summary
  of the same article, consulted for prior-coverage check, not treated as matt-harness doctrine).
- `docs/harness-decay-cadence.md`, `docs/METHODOLOGY.md`, `docs/reference/operating-model.md`,
  `docs/skill-authoring-conventions.md`, `CLAUDE.md` — all read against live repo state,
  v0.68.544.
