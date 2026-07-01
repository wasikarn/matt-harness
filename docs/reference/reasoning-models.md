# Reasoning models — common references

Single catalog of the named mental models the kbg-harness **already applies** or
**deliberately references without adopting**, with a pointer to where each one lives.
This is a *reference*, not a set of skills. kbg does **not** ship the models as
invokable skills — porting 39 thinking skills would violate METHODOLOGY Rule 2
(no speculative configurability) and YAGNI. This page names what the existing
skills already do, so the vocabulary is shared and discoverable from one place.

## Source + attribution

The named-model vocabulary and taxonomy are from
[**cc-thinking-skills**](https://github.com/tjboudreaux/cc-thinking-skills) by TJ Boudreaux
(MIT, © 2025) — 39 mental-model skills for Claude Code.

The full skill files are **vendored verbatim** as a common-references library under
`docs/reference/thinking-skills/` (commit `0313ee0`, MIT `LICENSE` retained). They are
stored under `docs/` deliberately — they are reference material, **not** invokable kbg
skills. Read a model's full write-up there; use the table below to find which kbg surface
already applies it.

> **Path note:** all internal paths below are shown as code-spans, not markdown links,
> because this file is read from the plugin cache and relative links would resolve against
> the user's project CWD, not the cache. Use the Bash recipes in the next section.

## The honesty caveat — read this first

cc-thinking-skills runs its own replication-gated eval pipeline and publishes the result
that **none of its 39 skills clears its own accuracy bar**:

> "no skill in this collection is proven to improve Claude's accuracy… Treat the skills as
> solid structured-reasoning scaffolds, not a guaranteed accuracy boost."

Zero skills hold a replicated **ELEVATE** verdict; `scientific-method` is only
*directional-not-replicated* (+5.3pp, p=0.061); and `margin-of-safety` measurably **hurt**
accuracy (87% → 77%, −10pp) in their run.

This is exactly why kbg references rather than adopts. A named model is a **framing
scaffold and a shared word**, not a correctness mechanism. The harness's correctness comes
from its *computational* feedback — the critical-hooks suite, the audit checks, the eval
gate — not from invoking a mental model. Same posture as the LLM-judge-circularity rule
(`CLAUDE.md`'s "Why — the unifying crux", under §Architecture): **use a model to structure
thinking; never cite "I applied model X" as evidence the work is right.**

> **Do not open this catalog unprompted.** Reasoning models are framing scaffolds, not a
> checklist to prepend to every task. Apply one only when the task explicitly calls for that
> lens; otherwise keep the catalog closed and rely on the existing kbg skills that already
> embed the relevant frames.

## How to use

Short-circuit rule (from their `thinking-model-router`): **if you already know the model,
just apply it — don't route.** This catalog is for the reverse direction — when a kbg skill
is doing something and you want the named handle for it (to combine lenses, to explain a
move, or to teach the harness's reasoning to someone new).

**Which scaffold for which situation?** That router is the METHODOLOGY scaffold menu ("Reach for a
reasoning scaffold when the call is hard," added v0.3.5) — `clarify-first` / `probe` / `decide` /
`strategize` / `critical-eval` / `doubt-driven`, split by reversibility. This catalog and its
tables below (model→home, workflow-pattern→models) are **reference**, not a competing
situation-router; for the 9 reference-only frames that no kbg skill applies, the on-demand path is
`kbg:inventory` (discovery escape hatch) + `docs/reference/thinking-skills/`.

To read the full upstream write-up for any model, run the Bash recipes in the next section.
**Do not use a `Read` tool on a literal `${KBG_PLUGIN_ROOT}` path** — the variable expands
only in shell context. The recipes also guard against the variable being unset, which happens
before restart or if `hooks/session/command-root-anchor.sh` did not run.

## Reading a vendored model from any project CWD

Run these in the **Bash** tool. `${KBG_PLUGIN_ROOT}` is exported by
`hooks/session/command-root-anchor.sh` on every SessionStart.

```bash
# Guard: the variable is only available after a successful SessionStart hook
: "${KBG_PLUGIN_ROOT:?KBG_PLUGIN_ROOT is not set — run 'claude plugin update kbg@kobig' and restart Claude Code}"

# List all 39 vendored mental models (directory names start with `thinking-`)
find "${KBG_PLUGIN_ROOT}/docs/reference/thinking-skills/skills" -maxdepth 2 -name SKILL.md \
  | sed 's|.*/skills/||; s|/SKILL.md||' | sort

# Read a specific model. Use the exact `Upstream dir` value from the table below
# (it always starts with `thinking-`). Do not strip the prefix.
cat "${KBG_PLUGIN_ROOT}/docs/reference/thinking-skills/skills/<thinking-dir>/SKILL.md"
# Example — read the systems-thinking vendored file (upstream dir is `thinking-systems`):
cat "${KBG_PLUGIN_ROOT}/docs/reference/thinking-skills/skills/thinking-systems/SKILL.md"

# Search the vendored models for a keyword
grep -Ril "<keyword>" "${KBG_PLUGIN_ROOT}/docs/reference/thinking-skills/skills"/*/SKILL.md
```

## Unified 39-model index

| Model | Upstream dir | kbg status | kbg home | How it shows up |
| --- | --- | --- | --- | --- |
| systems-thinking | `thinking-systems` | applied | skills/decide (probe mode) | named lens: systems-thinking + feedback loops (reinforcing/balancing) |
| feedback-loops | `thinking-feedback-loops` | applied | skills/decide (probe mode) | named step: mark loop as reinforcing or balancing |
| first-principles | `thinking-first-principles` | applied | skills/decide (probe mode) (Root Why) | probe one level deeper than the user's stated reason |
| second-order | `thinking-second-order` | applied | skills/decide (probe mode) (What-if) | 10x / fail / nothing consequence branches |
| pre-mortem | `thinking-pre-mortem` | applied | skills/decide (probe mode) | catastrophic-failure branch: what breaks first + detection + rollback |
| five-whys-plus | `thinking-five-whys-plus` | applied | skills/decide (probe mode) | Root Why probing; upstream name is five-whys-plus |
| thought-experiment | `thinking-thought-experiment` | applied | skills/decide (probe mode), /ideate | extreme-zero / extreme-infinite counterfactual frames |
| inversion | `thinking-inversion` | applied | /ideate | named ideate frame: ask the OPPOSITE question |
| reversibility | `thinking-reversibility` | applied | skills/domain-modeling, skills/decide (probe mode), the no-model-self-start rule (CLAUDE.md's Operating model under §Architecture) | "hard to reverse?" and "reversible in hours/days/never" |
| debiasing | `thinking-debiasing` | applied | skills/decide (probe mode) | Check yourself — anti-self-deception step |
| socratic | `thinking-socratic` | applied | skills/decide (clarify mode) | named method + "Socratic Trap" failure mode |
| scientific-method | `thinking-scientific-method` | applied | commands/fix-bug, skills/diagnosing-bugs | repro → hypothesize → instrument → falsify |
| theory-of-constraints | `thinking-theory-of-constraints` | considered | — | profile-first bottleneck-finding is thematic; skills/perf (its former kbg home) was deleted in the v0.6.0 reset, no live anchor |
| red-team | `thinking-red-team` | applied | skills/decide (critique mode) | Skeptic role: argue AGAINST and find risks |
| steel-manning | `thinking-steel-manning` | applied | skills/decide (critique mode) | Synthesizer: evaluate both sides; unconsidered alternatives |
| model-router | `thinking-model-router` | applied | skills/orchestrate | "pick the matrix" + 6-pattern dispatch vocabulary |
| model-selection | `thinking-model-selection` | applied | skills/orchestrate | "pick the matrix" + 6-pattern dispatch vocabulary |
| model-combination | `thinking-model-combination` | applied | skills/orchestrate | "pick the matrix" + 6-pattern dispatch vocabulary |
| opportunity-cost | `thinking-opportunity-cost` | applied | skills/orchestrate | frozen-bid test: compare spawn value vs doing it inline |
| circle-of-competence | `thinking-circle-of-competence` | applied | METHODOLOGY routing index, every agent | routing confidence + "defer to X" boundaries |
| jobs-to-be-done | `thinking-jobs-to-be-done` | considered | — | user-story-vs-job-to-be-done tradeoff is thematic; agents/product-analyst (its former kbg home) was deleted in the v0.6.0 reset, no live anchor |
| bayesian | `thinking-bayesian` | considered | commands/fix-bug, skills/incident | likelihood ranking is present, but model name is not used |
| probabilistic | `thinking-probabilistic` | considered | commands/fix-bug, skills/incident | likelihood ranking is present, but model name is not used |
| bounded-rationality | `thinking-bounded-rationality` | considered | skills/orchestrate | pick-the-matrix satisfices under constraints, but name is absent |
| margin-of-safety | `thinking-margin-of-safety` | considered | — | its former kbg home, agents/inferential-structural-judge, was deleted in the v0.6.3 Wave-B cut; measured to hurt accuracy −10pp in eval, not re-proposed |
| occams-razor | `thinking-occams-razor` | considered | METHODOLOGY Rule 2 | Simplicity First / minimum code, but frozen-bid test is explicitly opportunity-cost |
| map-territory | `thinking-map-territory` | considered | — | Read Before You Write, a METHODOLOGY rule dropped in the v0.6.0 reset; no live anchor |
| via-negativa | `thinking-via-negativa` | applied | skills/memory-lint (--trim mode) | named in footer: removal/absence as via-negativa |
| ooda | `thinking-ooda` | applied | skills/incident | named in incident footer (detect→assess→mitigate→monitor); the skill's hotfix path inherits via handoff |
| cynefin | `thinking-cynefin` | considered | skills/triage | triage classifies severity/scope, not problem domain |
| regret-minimization | `thinking-regret-minimization` | considered | — | asymmetry lens: recoverable downside vs permanently foregone upside; its former kbg home was deleted in the v0.6.0 reset, no live anchor |
| kepner-tregoe | `thinking-kepner-tregoe` | considered | — | no kbg anchor |
| triz | `thinking-triz` | considered | — | no kbg anchor |
| archetypes | `thinking-archetypes` | considered | — | no kbg anchor |
| effectuation | `thinking-effectuation` | considered | — | no kbg anchor |
| dual-process | `thinking-dual-process` | considered | — | (1) verification trigger: easy answer + high stakes → deliberate pass; (2) AI agent path design: fast-path (Haiku, no gate) vs slow-path (Sonnet + interrupt); its former kbg home was deleted in the v0.6.0 reset, no live anchor |
| fermi-estimation | `thinking-fermi-estimation` | considered | — | capacity planning, Redis/TimescaleDB sizing, ANPR throughput estimates before instrumentation exists; its former kbg home was deleted in the v0.6.0 reset, no live anchor |
| lindy-effect | `thinking-lindy-effect` | considered | — | no kbg anchor |
| leverage-points | `thinking-leverage-points` | considered | — | Meadows' 12-level hierarchy; when parameter tuning keeps not sticking, move up the hierarchy; its former kbg home was deleted in the v0.6.0 reset, no live anchor |

## kbg-native reasoning scaffolds

The kbg-harness ships its own structured-reasoning scaffolds alongside the vendored
cc-thinking-skills models. These are kbg-native processes, not part of the upstream
39-model catalog, and are invoked as kbg skills or read as reference docs.

| Scaffold | kbg surface | What it adds |
| --- | --- | --- |
| **judgment-ladder** | `kbg:decide` + `docs/reference/judgment-ladder.md` | A five-rung Decision Quality process for consequential choices: recognize → frame → test assumptions → estimate risk → decide, commit, and follow through. Use when the choice is analyzable and the cost of a bad decision exceeds the cost of a short structured pause. |
| **strategic-judgment** | `kbg:decide` strategize mode + `docs/reference/strategic-judgment.md` | A six-step strategic-judgment loop for irreversible commitments under ambiguity: diagnose → guiding policy → coherent actions → irreversibilities and real options → strategic red-team → commit to the strategy loop. Use when the commitment is large, long-lived, or hard to reverse and the diagnosis is contested. |

Read the full scaffold with Bash:

```bash
cat "${KBG_PLUGIN_ROOT}/docs/reference/judgment-ladder.md"
```

## Mapping models to Claude Code workflow patterns

The cc-thinking-skills collection is a vocabulary of structured-reasoning scaffolds.
kbg does **not** auto-route tasks through these models (that would be an
unattended model-router — excluded by the autonomy invariant per the no-model-self-start rule (CLAUDE.md's Operating model under §Architecture; read in Bash: `cat "${KBG_PLUGIN_ROOT}/CLAUDE.md"`).
Instead, each existing kbg skill already applies one or more models as a framing
lens. Use this table when you know the workflow pattern you are in and want the
named handle for the lens the relevant kbg surface already uses.

The six patterns below mirror the CC Workflow vocabulary documented in
`skills/orchestrate/reference.md §Dynamic-workflow pattern vocabulary`.
They are read-only framing labels, not dispatch instructions.

| Workflow pattern | When it applies | Mental models the kbg surface already uses | kbg surface to reach for |
|---|---|---|---|
| **classify-and-act** | Routing a task to the right lane (scope, priority, risk class) | `model-router`, `model-selection`, `model-combination`, `circle-of-competence`, `cynefin` | `kbg:orchestrate`, `kbg:triage`, `kbg:decide` clarify mode |
| **fan-out-and-synthesize** | N independent reads across disjoint slices, then merge | `systems-thinking`, `feedback-loops`, `thought-experiment`, `jobs-to-be-done`, `second-order` | `kbg:decide` probe mode, `/deep-dive` |
| **adversarial verification** | Judge produced work with a fresh-context skeptic | `red-team`, `steel-manning`, `debiasing`, `socratic`, `pre-mortem` | `kbg:decide` critique mode, `kbg:review-pr` |
| **generate-and-filter** | Produce N candidates, rank by rubric, return top-K | `inversion`, `thought-experiment`, `first-principles`, `opportunity-cost`, `occams-razor` | `/ideate`, `kbg:domain-modeling`, `/ship` scoping |
| **tournament** | N approaches compete; a rubric picks the winner | `steel-manning` + `red-team`, `bayesian` / `probabilistic` likelihood ranking, `jobs-to-be-done` tradeoff | `kbg:domain-modeling` (Pugh Matrix), `kbg:decide` critique mode |
| **loop-until-done** | Unknown work size; stop on observable criterion | `scientific-method`, `theory-of-constraints`, `five-whys-plus`, `reversibility`, `margin-of-safety` | `commands/fix-bug`, `kbg:recursive-improve` (human-gated), `kbg:orchestrate` per-task validation chain |

**Usage rule:** if a task already clearly matches a kbg surface, just use that
surface — don't invoke a model name separately. The model names are useful when
you want to explain *why* a surface is shaped the way it is, combine multiple
lenses explicitly, or teach the harness's reasoning to someone new.

## Status definitions

- **applied** — the model name appears explicitly in a kbg surface (skill, command, agent, or doctrine rule) as the lens being used.
- **considered** — the underlying practice appears in a kbg surface but the model name is not used, or the model is a valid lens with no concrete anchor.
- **rejected** — the model is explicitly excluded as a license for an unattended, model-judges-model loop per the autonomy invariant (the no-model-self-start rule, CLAUDE.md's Operating model under §Architecture; read in Bash: `cat "${KBG_PLUGIN_ROOT}/CLAUDE.md"`). It may still appear as *framing* inside an applied surface.

## Tathep domain scenarios

Cross-analysis of thinking models against the tathep project stack (10 repos: anpr-service, ai-agent-python, platform-api, website, admin, video-processing, player, app, bluedragon-eye-analytics-api, tathep-player). Use this table as a shortcut — when a tathep decision arises, find the scenario row and reach for the named surface.

### Already-covered scenarios (models embedded in existing kbg surfaces)

| Tathep scenario | Model | kbg surface |
|----------------|-------|-------------|
| Change PASS_GAP_SECONDS in production | pre-mortem + reversibility | `skills/decide` probe mode |
| Drop a TimescaleDB continuous_aggregate | reversibility | `skills/adr` |
| Leaderboard over-count root cause | scientific-method + five-whys | `commands/fix-bug` |
| ANPR throughput bottleneck (BullMQ / plate-read rate) | theory-of-constraints | `skills/latency-critical-systems` |
| Plate hashing algorithm change (SHA-256 → HMAC) | pre-mortem + reversibility | `skills/decide` + `skills/domain-modeling` (ADR) |
| LangGraph retry scope (which errors are retryable?) | second-order | `skills/cost-aware-llm-pipeline` |
| LangGraph agent loop diverges (debugging) | scientific-method | `skills/diagnosing-bugs` |
| LLM model routing (Haiku vs Sonnet) | opportunity-cost | `skills/cost-aware-llm-pipeline` |
| LangGraph tool result contains untrusted content | red-team | `skills/decide` |
| Effect-TS TryCatch consistency across 21 modules | systems-thinking | `skills/decide` |
| BullMQ failure — dead-letter vs retry | second-order | `skills/decide` |
| React Query cache invalidation strategy | second-order | `skills/decide` |
| Before every Cloudflare Pages deploy | pre-mortem | `skills/decide` |
| Dio interceptor error propagation (Flutter) | second-order | `skills/decide` |
| Firebase push notification routing (Flutter) | ooda | `skills/incident` |
| New campaign creation flow (advertiser JTBD) | jobs-to-be-done | `agents/product-analyst` |
| New module boundary in platform-api | circle-of-competence | `skills/decide` |
| Pages → App Router migration scope | reversibility | `skills/adr` |

### Previously-gap models (now applied via dedicated skills)

These four patterns recur in tathep and now have dedicated kbg surfaces. Use the skill directly.

**`fermi-estimation`** → `skills/fermi-estimation`. Three direct uses in anpr-service:
- plate-read rate per camera at peak → calibrate PASS_GAP_SECONDS without instrumentation
- Redis sorted-set memory growth per day (`50 cameras × 100k entries × ~50 bytes ≈ 250 MB/day`)
- TimescaleDB chunk compression trigger point

Quick order-of-magnitude check unlocks the engineering decision in 30 seconds. Currently deferred to instrumentation.

**`dual-process`** → `skills/dual-process`. Every `interrupt()` placement decision is a System 1 / System 2 question: fast-path (Haiku + no interrupt) vs slow-path (Sonnet + interrupt + human confirmation).

**`regret-minimization`** → `skills/regret-minimization`. For product and data-model decisions where both paths seem viable: whether to expose plate-level analytics (adds PDPA surface area, but opportunity closes), new module boundary commitments. Applies the asymmetry: recoverable downside vs permanently foregone upside.

**`leverage-points`** → `skills/leverage-points`. anpr-service has exactly one high-leverage point: plate-read rate. Improving it moves every downstream metric simultaneously. Use when parameter tuning keeps not sticking — move up Meadows' hierarchy instead of tuning the same parameter again.

### What thinking models cannot fill for tathep

These belong in repo-local CLAUDE.md files or the tathep wiki — not thinking-model territory:
- DOOH measurement standards (Geopath OTS/VAC formulas, IAB impression counting)
- Thai plate recognition edge cases (motorcycle plates, front-plate-only vehicles, occlusion patterns)
- BullMQ backpressure semantics (queue depth limits, stalled job recovery, priority ceiling)
- TimescaleDB cagg refresh watermark behavior across compressed vs uncompressed chunks
- LangGraph StateGraph conditional edge patterns (use context7 for current docs)
- Effect-TS pipe/flatMap composition idioms (reference, not model territory)
