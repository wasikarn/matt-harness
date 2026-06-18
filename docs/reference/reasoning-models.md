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
| systems-thinking | applied | skills/probe | the probe lens itself (Adam Bender, *Software Ecology*) |
| first-principles | applied | skills/probe (Root Why) | reframe stated reason → root constraint |
| second-order | applied | skills/probe (What-if) | 10x / fail / nothing consequence branches |
| pre-mortem | applied | skills/probe, agents/silent-failure-hunter | if this is wrong, what breaks first? + detection-latency rating |
| five-whys-plus | applied | skills/probe | constructive root-why, one level deeper |
| thought-experiment | applied | skills/probe, skills/ideate frames | counterfactual branches; extreme-zero / extreme-infinite |
| reversibility | applied | skills/adr, skills/probe, orchestrate L5, ADR 0002 | hard to reverse? is a first-class gate |
| debiasing | applied | skills/probe (anti-self-deception) | confirmation-bias / forced disconfirming-evidence step |
| socratic | applied | skills/clarify-first | names the method and its "Socratic Trap" failure mode |
| scientific-method | applied | commands/fix-bug, skills/perf | repro → hypothesize → falsify; perf's ">50% or discard" gate |
| theory-of-constraints | applied | skills/perf | profile → find the one bottleneck → fix that |
| via-negativa | applied | skills/decommission, skills/memory-trim, decay-cadence | improve by removing, not adding |
| red-team | applied | skills/critical-eval, agents/silent-failure-hunter, debug-debate Skeptic | institutionalized adversarial review |
| steel-manning | applied | debug-debate Synthesizer, skills/critical-eval | charitable alternative-coverage ("why dismissed — evidence or preference?") |
| model-router | applied | METHODOLOGY routing index, skills/orchestrate, skills/ideate | the dispatch layer *is* a router of approaches |
| model-selection | applied | METHODOLOGY routing index, skills/orchestrate, skills/ideate | the dispatch layer *is* a router of approaches |
| opportunity-cost | applied | skills/orchestrate (frozen-bid test), skills/ideate cost gate | is the spawn worth more than doing it inline? |
| bayesian | applied | commands/fix-bug, skills/incident | rank hypotheses by likelihood, re-rank on evidence |
| probabilistic | applied | commands/fix-bug, skills/incident | rank hypotheses by likelihood, re-rank on evidence |
| bounded-rationality | applied | skills/orchestrate (pick-the-matrix) | satisfice under constraints, don't optimize / false precision |
| margin-of-safety | applied | agent depth caps, structural-judge token headroom | "1 layer below the hard cap" |
| circle-of-competence | applied | every agent's "defer to X" boundary; METHODOLOGY routing confidence | stay in lane, escalate on no-match |
| map-territory | applied | METHODOLOGY Rule 8 (read before write); orchestrate stale-context-at-spawn | the doc ≠ the running system |
| jobs-to-be-done | applied | agents/product-analyst | named user-story-vs-JTBD tradeoff |
| occams-razor | applied | METHODOLOGY Rule 2; skills/orchestrate (frozen-bid test) | minimum that works; discard speculative branches early |
| ooda | considered | — | incident/perf/hotfix are phase pipelines; relabeling as OODA buys nothing the phases don't already give |
| cynefin | considered | — | triage classifies severity/scope, not problem domain (clear/complicated/complex/chaotic) |
| regret-minimization | considered | — | no kbg anchor; pure vocabulary |
| kepner-tregoe | considered | — | no kbg anchor; pure vocabulary |
| triz | considered | — | no kbg anchor; pure vocabulary |
| archetypes | considered | — | no kbg anchor; pure vocabulary ("systems-archetypes") |
| effectuation | considered | — | no kbg anchor; pure vocabulary |
| dual-process | considered | — | no kbg anchor; pure vocabulary |
| fermi-estimation | considered | — | no kbg anchor; pure vocabulary |
| lindy-effect | considered | — | no kbg anchor; pure vocabulary |
| inversion | considered | — | for risk work, pre-mortem is the richer tool; use inversion only for quick failure-mode enumeration |
| leverage-points | considered | — | no direct anchor beyond systems-thinking/probe |
| feedback-loops | rejected | skills/probe | referenced as *framing* only — never as license for a closed model-judges-model loop (ADR 0002) |
| model-combination | rejected | METHODOLOGY routing index, skills/orchestrate, skills/ideate | referenced as *framing* only — never as license for a closed model-judges-model loop (ADR 0002) |

## Status definitions

- **applied** — kbg has a concrete surface (skill, command, agent, or doctrine rule) that uses this model; the model is not just vocabulary.
- **considered** — the model is a valid lens but kbg already covers the same ground with a stronger surface, or it has no anchor beyond vocabulary.
- **rejected** — the model is explicitly excluded as a license for an unattended, model-judges-model loop per the autonomy invariant ([ADR 0002](../adr/0002-autonomy-invariant.md)). It may still appear as *framing* inside an applied surface.
