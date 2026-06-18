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
(`CLAUDE.md` §LLM-judge-circularity): **use a model to structure thinking; never cite "I
applied model X" as evidence the work is right.**

> **Do not open this catalog unprompted.** Reasoning models are framing scaffolds, not a
> checklist to prepend to every task. Apply one only when the task explicitly calls for that
> lens; otherwise keep the catalog closed and rely on the existing kbg skills that already
> embed the relevant frames.

## How to use

Short-circuit rule (from their `thinking-model-router`): **if you already know the model,
just apply it — don't route.** This catalog is for the reverse direction — when a kbg skill
is doing something and you want the named handle for it (to combine lenses, to explain a
move, or to teach the harness's reasoning to someone new).

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
find "${KBG_PLUGIN_ROOT}"/docs/reference/thinking-skills/skills -maxdepth 2 -name SKILL.md \
  | sed 's|.*/skills/||; s|/SKILL.md||' | sort

# Read a specific model. Use the exact `Upstream dir` value from the table below
# (it always starts with `thinking-`). Do not strip the prefix.
cat "${KBG_PLUGIN_ROOT}/docs/reference/thinking-skills/skills/<thinking-dir>/SKILL.md"
# Example — read the systems-thinking vendored file (upstream dir is `thinking-systems`):
cat "${KBG_PLUGIN_ROOT}/docs/reference/thinking-skills/skills/thinking-systems/SKILL.md"

# Search the vendored models for a keyword
grep -Ril "<keyword>" "${KBG_PLUGIN_ROOT}"/docs/reference/thinking-skills/skills/*/SKILL.md
```

## Unified 39-model index

| Model | Upstream dir | kbg status | kbg home | How it shows up |
| --- | --- | --- | --- | --- |
| systems-thinking | `thinking-systems` | applied | skills/probe | named lens: systems-thinking + feedback loops (reinforcing/balancing) |
| feedback-loops | `thinking-feedback-loops` | applied | skills/probe | named step: mark loop as reinforcing or balancing |
| first-principles | `thinking-first-principles` | applied | skills/probe (Root Why) | probe one level deeper than the user's stated reason |
| second-order | `thinking-second-order` | applied | skills/probe (What-if) | 10x / fail / nothing consequence branches |
| pre-mortem | `thinking-pre-mortem` | applied | skills/probe | catastrophic-failure branch: what breaks first + detection + rollback |
| five-whys-plus | `thinking-five-whys-plus` | applied | skills/probe | Root Why probing; upstream name is five-whys-plus |
| thought-experiment | `thinking-thought-experiment` | applied | skills/probe, skills/ideate | extreme-zero / extreme-infinite counterfactual frames |
| inversion | `thinking-inversion` | applied | skills/ideate | named ideate frame: ask the OPPOSITE question |
| reversibility | `thinking-reversibility` | applied | skills/adr, skills/probe, ADR 0002 | "hard to reverse?" and "reversible in hours/days/never" |
| debiasing | `thinking-debiasing` | applied | skills/probe | Check yourself — anti-self-deception step |
| socratic | `thinking-socratic` | applied | skills/clarify-first | named method + "Socratic Trap" failure mode |
| scientific-method | `thinking-scientific-method` | applied | commands/fix-bug, skills/perf | repro → hypothesize → instrument → falsify |
| theory-of-constraints | `thinking-theory-of-constraints` | applied | skills/perf | profile → find the one bottleneck → fix that |
| red-team | `thinking-red-team` | applied | skills/critical-eval, commands/debug-debate | Skeptic role: argue AGAINST and find risks |
| steel-manning | `thinking-steel-manning` | applied | skills/critical-eval, commands/debug-debate | Synthesizer: evaluate both sides; unconsidered alternatives |
| model-router | `thinking-model-router` | applied | skills/orchestrate | "pick the matrix" + 6-pattern dispatch vocabulary |
| model-selection | `thinking-model-selection` | applied | skills/orchestrate | "pick the matrix" + 6-pattern dispatch vocabulary |
| model-combination | `thinking-model-combination` | applied | skills/orchestrate | "pick the matrix" + 6-pattern dispatch vocabulary |
| opportunity-cost | `thinking-opportunity-cost` | applied | skills/orchestrate | frozen-bid test: compare spawn value vs doing it inline |
| circle-of-competence | `thinking-circle-of-competence` | applied | METHODOLOGY routing index, every agent | routing confidence + "defer to X" boundaries |
| jobs-to-be-done | `thinking-jobs-to-be-done` | applied | agents/product-analyst | named tradeoff: user story vs job-to-be-done |
| bayesian | `thinking-bayesian` | considered | commands/fix-bug, skills/incident | likelihood ranking is present, but model name is not used |
| probabilistic | `thinking-probabilistic` | considered | commands/fix-bug, skills/incident | likelihood ranking is present, but model name is not used |
| bounded-rationality | `thinking-bounded-rationality` | considered | skills/orchestrate | pick-the-matrix satisfices under constraints, but name is absent |
| margin-of-safety | `thinking-margin-of-safety` | considered | agents/inferential-structural-judge | 5k-token headroom below budget; "agent depth caps" is thematic, not named |
| occams-razor | `thinking-occams-razor` | considered | METHODOLOGY Rule 2 | Simplicity First / minimum code, but frozen-bid test is explicitly opportunity-cost |
| map-territory | `thinking-map-territory` | considered | METHODOLOGY Rule 8 | Read Before You Write; no named stale-context-at-spawn surface |
| via-negativa | `thinking-via-negativa` | considered | skills/decommission, skills/memory-trim | removal-first practice; model name not used |
| ooda | `thinking-ooda` | considered | skills/incident, skills/hotfix | incident phases are observe-orient-decide-act shaped, but not relabeled |
| cynefin | `thinking-cynefin` | considered | skills/triage | triage classifies severity/scope, not problem domain |
| regret-minimization | `thinking-regret-minimization` | considered | — | no kbg anchor |
| kepner-tregoe | `thinking-kepner-tregoe` | considered | — | no kbg anchor |
| triz | `thinking-triz` | considered | — | no kbg anchor |
| archetypes | `thinking-archetypes` | considered | — | no kbg anchor |
| effectuation | `thinking-effectuation` | considered | — | no kbg anchor |
| dual-process | `thinking-dual-process` | considered | — | no kbg anchor |
| fermi-estimation | `thinking-fermi-estimation` | considered | — | no kbg anchor |
| lindy-effect | `thinking-lindy-effect` | considered | — | no kbg anchor |
| leverage-points | `thinking-leverage-points` | considered | — | no direct anchor beyond systems-thinking/probe |

## Mapping models to Claude Code workflow patterns

The cc-thinking-skills collection is a vocabulary of structured-reasoning scaffolds.
kbg does **not** auto-route tasks through these models (that would be an
unattended model-router — excluded by the autonomy invariant per ADR 0002; read in Bash: `cat "${KBG_PLUGIN_ROOT}/docs/adr/0002-autonomy-invariant.md"`).
Instead, each existing kbg skill already applies one or more models as a framing
lens. Use this table when you know the workflow pattern you are in and want the
named handle for the lens the relevant kbg surface already uses.

The six patterns below mirror the CC Workflow vocabulary documented in
`skills/orchestrate/reference.md §Dynamic-workflow pattern vocabulary`.
They are read-only framing labels, not dispatch instructions.

| Workflow pattern | When it applies | Mental models the kbg surface already uses | kbg surface to reach for |
|---|---|---|---|
| **classify-and-act** | Routing a task to the right lane (scope, priority, risk class) | `model-router`, `model-selection`, `model-combination`, `circle-of-competence`, `cynefin` | `kbg:orchestrate`, `kbg:triage`, `kbg:clarify-first` |
| **fan-out-and-synthesize** | N independent reads across disjoint slices, then merge | `systems-thinking`, `feedback-loops`, `thought-experiment`, `jobs-to-be-done`, `second-order` | `kbg:probe`, `kbg:research-brief`, `kbg:article-mine` |
| **adversarial verification** | Judge produced work with a fresh-context skeptic | `red-team`, `steel-manning`, `debiasing`, `socratic`, `pre-mortem` | `kbg:critical-eval`, `commands/debug-debate`, `kbg:review-pr` |
| **generate-and-filter** | Produce N candidates, rank by rubric, return top-K | `inversion`, `thought-experiment`, `first-principles`, `opportunity-cost`, `occams-razor` | `kbg:ideate`, `kbg:adr`, `/feature-dev` scoping |
| **tournament** | N approaches compete; a rubric picks the winner | `steel-manning` + `red-team`, `bayesian` / `probabilistic` likelihood ranking, `jobs-to-be-done` tradeoff | `kbg:adr` (Pugh Matrix), `/debug-debate` |
| **loop-until-done** | Unknown work size; stop on observable criterion | `scientific-method`, `theory-of-constraints`, `five-whys-plus`, `reversibility`, `margin-of-safety` | `commands/fix-bug`, `kbg:recursive-improve` (human-gated), `/validate-and-fix` |

**Usage rule:** if a task already clearly matches a kbg surface, just use that
surface — don't invoke a model name separately. The model names are useful when
you want to explain *why* a surface is shaped the way it is, combine multiple
lenses explicitly, or teach the harness's reasoning to someone new.

## Status definitions

- **applied** — the model name appears explicitly in a kbg surface (skill, command, agent, or doctrine rule) as the lens being used.
- **considered** — the underlying practice appears in a kbg surface but the model name is not used, or the model is a valid lens with no concrete anchor.
- **rejected** — the model is explicitly excluded as a license for an unattended, model-judges-model loop per the autonomy invariant (read ADR 0002 in Bash: `cat "${KBG_PLUGIN_ROOT}/docs/adr/0002-autonomy-invariant.md"`). It may still appear as *framing* inside an applied surface.
