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

The full skill files are **vendored verbatim** as a common-references library at
[`thinking-skills/`](thinking-skills/) (commit `0313ee0`, MIT `LICENSE` retained). They are
stored under `docs/` deliberately — they are reference material, **not** invokable kbg
skills (see [`thinking-skills/README.md`](thinking-skills/README.md)). Read a model's full
write-up there; use the table below to find which kbg surface already applies it.

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

## How to use

Short-circuit rule (from their `thinking-model-router`): **if you already know the model,
just apply it — don't route.** This catalog is for the reverse direction — when a kbg skill
is doing something and you want the named handle for it (to combine lenses, to explain a
move, or to teach the harness's reasoning to someone new).

To read the full upstream write-up for any model, run the Bash recipes in the next section.
Do not use a `Read` tool on a literal `${KBG_PLUGIN_ROOT}` path — the variable expands
only in shell context.

## Reading a vendored model from any project CWD

Run these in the **Bash** tool. `${KBG_PLUGIN_ROOT}` is exported by
`hooks/session/command-root-anchor.sh` on every SessionStart.

```bash
# List all 39 vendored mental models
find "${KBG_PLUGIN_ROOT}"/docs/reference/thinking-skills/skills -maxdepth 2 -name SKILL.md \
  | sed 's|.*/skills/||; s|/SKILL.md||' | sort

# Read a specific model by its upstream directory name
cat "${KBG_PLUGIN_ROOT}/docs/reference/thinking-skills/skills/thinking-<name>/SKILL.md"

# Search the vendored models for a keyword
grep -Ril "<keyword>" "${KBG_PLUGIN_ROOT}"/docs/reference/thinking-skills/skills/*/SKILL.md
```

## Unified 39-model index

| Model | kbg status | kbg home | How it shows up |
|---|---|---|---|
| systems-thinking | applied | skills/probe | named lens: systems-thinking + feedback loops (reinforcing/balancing) |
| feedback-loops | applied | skills/probe | named step: mark loop as reinforcing or balancing |
| first-principles | applied | skills/probe (Root Why) | probe one level deeper than the user's stated reason |
| second-order | applied | skills/probe (What-if) | 10x / fail / nothing consequence branches |
| pre-mortem | applied | skills/probe | catastrophic-failure branch: what breaks first + detection + rollback |
| five-whys-plus | applied | skills/probe | Root Why probing; upstream name is five-whys-plus |
| thought-experiment | applied | skills/probe, skills/ideate | extreme-zero / extreme-infinite counterfactual frames |
| inversion | applied | skills/ideate | named ideate frame: ask the OPPOSITE question |
| reversibility | applied | skills/adr, skills/probe, ADR 0002 | "hard to reverse?" and "reversible in hours/days/never" |
| debiasing | applied | skills/probe | Check yourself — anti-self-deception step |
| socratic | applied | skills/clarify-first | named method + "Socratic Trap" failure mode |
| scientific-method | applied | commands/fix-bug, skills/perf | repro → hypothesize → instrument → falsify |
| theory-of-constraints | applied | skills/perf | profile → find the one bottleneck → fix that |
| red-team | applied | skills/critical-eval, commands/debug-debate | Skeptic role: argue AGAINST and find risks |
| steel-manning | applied | skills/critical-eval, commands/debug-debate | Synthesizer: evaluate both sides; unconsidered alternatives |
| model-router | applied | skills/orchestrate | "pick the matrix" + 6-pattern dispatch vocabulary |
| model-selection | applied | skills/orchestrate | "pick the matrix" + 6-pattern dispatch vocabulary |
| model-combination | applied | skills/orchestrate | "pick the matrix" + 6-pattern dispatch vocabulary |
| opportunity-cost | applied | skills/orchestrate | frozen-bid test: compare spawn value vs doing it inline |
| circle-of-competence | applied | METHODOLOGY routing index, every agent | routing confidence + "defer to X" boundaries |
| jobs-to-be-done | applied | agents/product-analyst | named tradeoff: user story vs job-to-be-done |
| bayesian | considered | commands/fix-bug, skills/incident | likelihood ranking is present, but model name is not used |
| probabilistic | considered | commands/fix-bug, skills/incident | likelihood ranking is present, but model name is not used |
| bounded-rationality | considered | skills/orchestrate | pick-the-matrix satisfices under constraints, but name is absent |
| margin-of-safety | considered | agents/inferential-structural-judge | 5k-token headroom below budget; "agent depth caps" is thematic, not named |
| occams-razor | considered | METHODOLOGY Rule 2 | Simplicity First / minimum code, but frozen-bid test is explicitly opportunity-cost |
| map-territory | considered | METHODOLOGY Rule 8 | Read Before You Write; no named stale-context-at-spawn surface |
| via-negativa | considered | skills/decommission, skills/memory-trim | removal-first practice; model name not used |
| ooda | considered | skills/incident, skills/hotfix | incident phases are observe-orient-decide-act shaped, but not relabeled |
| cynefin | considered | skills/triage | triage classifies severity/scope, not problem domain |
| regret-minimization | considered | — | no kbg anchor |
| kepner-tregoe | considered | — | no kbg anchor |
| triz | considered | — | no kbg anchor |
| archetypes | considered | — | no kbg anchor |
| effectuation | considered | — | no kbg anchor |
| dual-process | considered | — | no kbg anchor |
| fermi-estimation | considered | — | no kbg anchor |
| lindy-effect | considered | — | no kbg anchor |
| leverage-points | considered | — | no direct anchor beyond systems-thinking/probe |

## Status definitions

- **applied** — the model name appears explicitly in a kbg surface (skill, command, agent, or doctrine rule) as the lens being used.
- **considered** — the underlying practice appears in a kbg surface but the model name is not used, or the model is a valid lens with no concrete anchor.
- **rejected** — the model is explicitly excluded as a license for an unattended, model-judges-model loop per the autonomy invariant ([ADR 0002](../adr/0002-autonomy-invariant.md)). It may still appear as *framing* inside an applied surface.
