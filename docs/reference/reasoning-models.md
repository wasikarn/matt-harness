# Reasoning models — common references

Single catalog of the named mental models the kbg-harness **already applies**, with a
pointer to where each one lives. This is a *reference*, not a set of skills. kbg does
**not** ship the models as invokable skills — porting 39 thinking skills would violate
METHODOLOGY Rule 2 (no speculative configurability) and YAGNI. This page names what the
existing skills already do, so the vocabulary is shared and discoverable from one place.

## Source + attribution

The named-model vocabulary and taxonomy are from
**[cc-thinking-skills](https://github.com/tjboudreaux/cc-thinking-skills)** by TJ Boudreaux
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

## Where kbg already applies these

| Model | kbg home | How it shows up |
|---|---|---|
| systems-thinking | `skills/probe` | the probe lens itself (Adam Bender, *Software Ecology*) |
| feedback-loops | `skills/probe` | reinforcing vs balancing, named |
| first-principles | `skills/probe` (Root Why) | reframe stated reason → root constraint |
| second-order | `skills/probe` (What-if) | 10x / fail / nothing consequence branches |
| pre-mortem | `skills/probe`, `agents/silent-failure-hunter` | "if this is wrong, what breaks first?" + detection-latency rating |
| five-whys | `skills/probe` | constructive root-why, one level deeper |
| thought-experiment | `skills/probe`, `skills/ideate` frames | counterfactual branches; extreme-zero / extreme-infinite |
| reversibility (Type-1/2) | `skills/adr`, `skills/probe`, `orchestrate` L5, ADR 0002 | "hard to reverse?" is a first-class gate |
| debiasing | `skills/probe` (anti-self-deception) | confirmation-bias / forced disconfirming-evidence step |
| socratic | `skills/clarify-first` | names the method **and** its "Socratic Trap" failure mode |
| scientific-method | `commands/fix-bug`, `skills/perf` | repro → hypothesize → falsify; perf's ">50% or discard" gate |
| theory-of-constraints | `skills/perf` | profile → find the one bottleneck → fix that |
| via-negativa | `skills/decommission`, `skills/memory-trim`, decay-cadence | improve by removing, not adding |
| red-team | `skills/critical-eval`, `agents/silent-failure-hunter`, debug-debate Skeptic | institutionalized adversarial review |
| steel-manning | debug-debate Synthesizer, `skills/critical-eval` | charitable alternative-coverage ("why dismissed — evidence or preference?") |
| model-router / -selection / -combination | METHODOLOGY routing index, `skills/orchestrate` "pick the matrix" + 6-pattern vocabulary, `skills/ideate` frame pool | the dispatch layer *is* a router of approaches |
| opportunity-cost | `skills/orchestrate` (frozen-bid test), `skills/ideate` cost gate | "is the spawn worth more than doing it inline?" |
| bayesian / probabilistic | `commands/fix-bug`, `skills/incident` | rank hypotheses by likelihood, re-rank on evidence |
| bounded-rationality | `skills/orchestrate` (pick-the-matrix, "no numeric scoring / false precision") | satisfice under constraints, don't optimize |
| margin-of-safety | agent depth caps (`code-explorer`, `researcher`), structural-judge token headroom | "1 layer below the hard cap" |
| circle-of-competence | every agent's "defer to X" boundary; METHODOLOGY routing confidence | stay in lane, escalate on no-match |
| map-territory | METHODOLOGY Rule 8 (read before write); orchestrate stale-context-at-spawn | the doc ≠ the running system |
| jobs-to-be-done | `agents/product-analyst` | named user-story-vs-JTBD tradeoff |
| occams-razor | METHODOLOGY Rule 2; `skills/orchestrate` (frozen-bid test) | minimum that works; discard speculative branches early |

## Considered, not adopted

Naming a model with no existing behavior to anchor it is vocabulary for vocabulary's sake
(Rule 2). These were checked and deliberately left unnamed:

- **OODA** — `incident` / `perf` / `hotfix` are phase pipelines that *could* be relabelled
  observe-orient-decide-act, but the relabel buys nothing the phases don't already give.
  Candidate only if a future loop genuinely needs the orient step called out.
- **cynefin** — `triage` classifies severity/scope, not problem domain
  (clear / complicated / complex / chaotic). Worth revisiting only if triage starts
  mis-routing complex-domain work as if it were clear.
- **regret-minimization, kepner-tregoe, TRIZ, systems-archetypes, effectuation,
  dual-process, fermi-estimation, lindy-effect** — no anchor; pure vocabulary. Left out.

## Rejected by doctrine

Any meta-model framed as enabling an **unattended, model-judges-model loop** is foreclosed
by the autonomy invariant ([ADR 0002](../adr/0002-autonomy-invariant.md)). `model-combination`
and `feedback-loops` are referenced here as *framing* only — never as license for a closed
self-iteration loop. Inferential-feedback sensors stay advisory-only
(`CLAUDE.md` §LLM-judge-circularity).
