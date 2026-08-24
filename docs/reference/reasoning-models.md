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

### External verification (2026-07-14)

A user request to wrap the 39 files as a dispatchable agent triggered a deep-research pass
against Anthropic's official docs and independent sources
(github.com/tjboudreaux/cc-thinking-skills, code.claude.com/docs/en/skills,
anthropic.com/engineering). Verdict: **the no-wrapper conclusion holds, on different grounds
than "auto-triggering a skill without a human naming it first is itself a flagged
anti-pattern"** — that specific framing is **not** supported; official docs describe
description-matched auto-invocation as Skills' designed default, not a risk to guard
against. Drop that framing if it resurfaces. What **is** well-evidenced:

- **Evaluation-first gate, unmet.** Anthropic's own skill-authoring guidance: build evals
  against demonstrated task failures *before* writing skill content, not "documented
  imagined problems." cc-thinking-skills' own scorecard shows **zero of 39 models hold a
  replicated ELEVATE verdict** and `margin-of-safety` measured a −10pp regression — there is
  no demonstrated capability gap to justify the build right now.
- **Tool/skill-surface proliferation is a named Anthropic anti-pattern.** "Too many tools or
  overlapping tools... distract agents from pursuing efficient strategies" and create
  "ambiguous decision points about which tool to use" — a near-exact description of 39
  near-synonymous named frameworks each promoted to its own skill.
- **Token cost is concrete, not hypothetical, at kbg's actual scale.** Skill metadata loads
  into every session regardless of use (~100 tokens/skill); kbg runs 33 live skills today —
  wrapping all 39 thinking models would roughly **double** that count and add ~3,900
  always-on tokens against Claude Code's skill-listing eviction budget (~1,536 + 1% of
  context — see `skill-listing-budget-mechanics` memory), for zero proven behavior change.
- **The specific risk this doctrine names is real, not hypothetical.** Upstream ships its
  own `thinking-model-router` skill that free-text-selects among the 39 with **no**
  `disable-model-invocation` gate — confirmed present in kbg's own vendored copy too. What
  actually keeps kbg's install unexposed is the **directory placement** — `docs/reference/`,
  outside the auto-discovered `skills/` tree Claude Code scans at startup — not a
  content-level safeguard. That placement is load-bearing; don't let a future sync (e.g. a
  `gh skill install` pass, or copying a file "for convenience") promote any of these 39
  files, or a new skill built on top of one, into `skills/` without deliberately clearing
  the evaluation-first bar above first.

## How to use

Short-circuit rule (from their `thinking-model-router`): **if you already know the model,
just apply it — don't route.** This catalog is for the reverse direction — when a kbg skill
is doing something and you want the named handle for it (to combine lenses, to explain a
move, or to teach the harness's reasoning to someone new).

**Which scaffold for which situation?** That router is
`docs/reference/decision-doctrine-map.md` (situation → scaffold → owning rule, picked by
reversibility). This catalog and its
tables below (model→home, workflow-pattern→models) are **reference**, not a competing
situation-router; for the reference-only frames that no kbg skill applies (the model→home table
below marks each), the on-demand path is
`BOUNDARY.md` (the generated capability map — the `inventory` skill wrapper was removed
2026-08-24 #80) + `docs/reference/thinking-skills/`.

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

> **Former-home note.** Several rows below carried the since-deleted `skills/decide`
> skill as their kbg home (deleted 2026-08-24, ticket 79 — `mattpocock-skills:grilling`
> is now the fleet's adversarial pressure-testing surface). Those rows now read
> `considered` / `—`, the same convention as the v0.6.0-reset rows. Statuses were
> last recalibrated 2026-07-20 — see
> `kbg-decide-zero-real-world-invocations-2026-07-02.md` for that audit.

| Model | Upstream dir | kbg status | kbg home | How it shows up |
| --- | --- | --- | --- | --- |
| systems-thinking | `thinking-systems` | considered | — | map-the-system lens (actors, flows, feedback loops, delays); its former kbg home was deleted 2026-08-24, no live anchor |
| feedback-loops | `thinking-feedback-loops` | considered | — | reinforcing-vs-balancing loops as a reference frame to pull in manually; its former kbg home was deleted 2026-08-24, no live anchor |
| first-principles | `thinking-first-principles` | considered | — | "probe one level deeper" Root-Why frame to pull in manually; its former kbg home was deleted 2026-08-24, no live anchor |
| second-order | `thinking-second-order` | considered | — | 10x/fail/nothing what-if branches as a reference frame to pull in manually; its former kbg home was deleted 2026-08-24, no live anchor |
| pre-mortem | `thinking-pre-mortem` | applied | commands/post-mortem (Escape Reason) | catastrophic-failure branch: what breaks first + detection + rollback — genuinely operationalized in post-mortem (its former review-pr home was deleted 2026-08-24 #82) |
| five-whys-plus | `thinking-five-whys-plus` | considered | — | Root-Why probing as a reference frame to pull in manually; its former kbg home was deleted 2026-08-24, no live anchor |
| thought-experiment | `thinking-thought-experiment` | applied | /ideate | extreme-zero / extreme-infinite counterfactual frames — genuinely operationalized as a named ideate frame |
| inversion | `thinking-inversion` | applied | /ideate | named ideate frame: ask the OPPOSITE question |
| reversibility | `thinking-reversibility` | applied | domain-modeling, the no-model-self-start rule (CLAUDE.md's Operating model under §Architecture) | "hard to reverse?" and "reversible in hours/days/never" — genuinely operationalized in domain-modeling/the no-self-start rule |
| debiasing | `thinking-debiasing` | considered | — | Check yourself — anti-self-deception frame; its former kbg home was deleted 2026-08-24, no live anchor |
| socratic | `thinking-socratic` | considered | — | named-method questioning + "Socratic Trap" failure mode; its former kbg home was deleted 2026-08-24, no live anchor |
| scientific-method | `thinking-scientific-method` | applied | diagnosing-bugs, commands/post-mortem (Discovery + Validation) | repro → hypothesize → instrument → falsify |
| theory-of-constraints | `thinking-theory-of-constraints` | applied | agents/performance-optimizer.md | profile first to find the actual constraint; don't optimize the 95% that isn't the rate-limiter (added v0.30.2, superseding its deleted skills/perf home from the v0.6.0 reset) |
| red-team | `thinking-red-team` | considered | — | Skeptic role: argue AGAINST and find risks; its former kbg home (review-pr) was deleted 2026-08-24 #82, no live anchor |
| steel-manning | `thinking-steel-manning` | applied | skills/score-decision | Synthesizer: evaluate both sides; unconsidered alternatives (its former review-pr home was deleted 2026-08-24 #82) |
| model-router | `thinking-model-router` | applied | skills/orchestrate | "pick the matrix" + 6-pattern dispatch vocabulary |
| model-selection | `thinking-model-selection` | applied | skills/orchestrate | "pick the matrix" + 6-pattern dispatch vocabulary |
| model-combination | `thinking-model-combination` | applied | skills/orchestrate | "pick the matrix" + 6-pattern dispatch vocabulary |
| opportunity-cost | `thinking-opportunity-cost` | applied | skills/orchestrate | frozen-bid test: compare spawn value vs doing it inline |
| circle-of-competence | `thinking-circle-of-competence` | applied | METHODOLOGY routing index, every agent | routing confidence + "defer to X" boundaries |
| jobs-to-be-done | `thinking-jobs-to-be-done` | considered | — | user-story-vs-job-to-be-done tradeoff is thematic; agents/product-analyst (its former kbg home) was deleted in the v0.6.0 reset, no live anchor |
| bayesian | `thinking-bayesian` | considered | diagnosing-bugs, skills/incident | likelihood ranking is present, but model name is not used |
| probabilistic | `thinking-probabilistic` | considered | diagnosing-bugs, skills/incident | likelihood ranking is present, but model name is not used |
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
| leverage-points | `thinking-leverage-points` | applied | agents/performance-optimizer.md, skills/score-decision (single-criterion-that-flips trace) | a small number of places have outsized effect — find them before tuning the rest (added v0.30.2, superseding its deleted former home from the v0.6.3 Wave-B cut); Meadows' 12-level hierarchy applies when parameter tuning keeps not sticking |

## kbg-native reasoning scaffolds

The kbg-harness ships its own structured-reasoning scaffolds alongside the vendored
cc-thinking-skills models. These are kbg-native processes, not part of the upstream
39-model catalog, and are read as reference docs and applied inline.

| Scaffold | kbg surface | What it adds |
| --- | --- | --- |
| **judgment-ladder** | `docs/reference/judgment-ladder.md` | A five-rung Decision Quality process for consequential choices: recognize → frame → test assumptions → estimate risk → decide, commit, and follow through. Use when the choice is analyzable and the cost of a bad decision exceeds the cost of a short structured pause. |
| **strategic-judgment** | `docs/reference/strategic-judgment.md` | A six-step strategic-judgment loop for irreversible commitments under ambiguity: diagnose → guiding policy → coherent actions → irreversibilities and real options → strategic red-team → commit to the strategy loop. Use when the commitment is large, long-lived, or hard to reverse and the diagnosis is contested. |

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
| **classify-and-act** | Routing a task to the right lane (scope, priority, risk class) | `model-router`, `model-selection`, `model-combination`, `circle-of-competence`, `cynefin` | `kbg:orchestrate`, `triage` |
| **fan-out-and-synthesize** | N independent reads across disjoint slices, then merge | `systems-thinking`, `feedback-loops`, `thought-experiment`, `jobs-to-be-done`, `second-order` | `research` |
| **adversarial verification** | Judge produced work with a fresh-context skeptic | `red-team`, `steel-manning`, `debiasing`, `socratic`, `pre-mortem` | `mattpocock-skills:code-review`, `mattpocock-skills:grilling` |
| **generate-and-filter** | Produce N candidates, rank by rubric, return top-K | `inversion`, `thought-experiment`, `first-principles`, `opportunity-cost`, `occams-razor` | `/ideate`, `domain-modeling` |
| **tournament** | N approaches compete; a rubric picks the winner | `steel-manning` + `red-team`, `bayesian` / `probabilistic` likelihood ranking, `jobs-to-be-done` tradeoff | `domain-modeling` (Pugh Matrix) |
| **loop-until-done** | Unknown work size; stop on observable criterion | `scientific-method`, `theory-of-constraints`, `five-whys-plus`, `reversibility`, `margin-of-safety` | `mattpocock-skills:diagnosing-bugs`, `kbg:recursive-improve` (human-gated), `kbg:orchestrate` per-task validation chain |

**Usage rule:** if a task already clearly matches a kbg surface, just use that
surface — don't invoke a model name separately. The model names are useful when
you want to explain *why* a surface is shaped the way it is, combine multiple
lenses explicitly, or teach the harness's reasoning to someone new.

## Status definitions

- **applied** — the model name appears explicitly in a kbg surface (skill, command, agent, or doctrine rule) as the lens being used.
- **considered** — the underlying practice appears in a kbg surface but the model name is not used, or the model is a valid lens with no concrete anchor.
- **rejected** — the model is explicitly excluded as a license for an unattended, model-judges-model loop per the autonomy invariant (the no-model-self-start rule, CLAUDE.md's Operating model under §Architecture; read in Bash: `cat "${KBG_PLUGIN_ROOT}/CLAUDE.md"`). It may still appear as *framing* inside an applied surface.
