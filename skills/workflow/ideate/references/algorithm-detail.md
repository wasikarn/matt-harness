# ideate — exact prompts, rubric mechanics, output-shape detail

Moved verbatim out of the skill's main file (2026-08-23, 200-LOC cap refactor; that file was
COMMAND.md until the commands-to-skills conversion folded it into SKILL.md, 2026-08-25).
SKILL.md keeps the control flow and every invariant; this file carries the literal templates
read at execution time. Provenance for all of it: `provenance.md`.

## Phase 1 — Diverge payload (per Agent call)

```
PROBLEM:
{problem}

{context ? `CONTEXT:\n${context}\n\n` : ""}FRAME — {frame.label}:
{frame.prompt}

Generate {ideasPerFrame} ideas under this frame.
Output JSON array only. No prose before or after.
[{"text": "...", "rationale": "..."}, ...]
```

## Phase 1 — Diverge system prompt (per Agent call)

> You are in DIVERGENT mode. You are a generator, not a critic.
> Generate 6 short distinct ideas under this frame. Each idea is
> one phrase or one sentence. Do not evaluate. Do not rank. Do
> not hedge. The first three obvious answers everyone would
> give are banned. Push past them into the awkward middle.
> Output a JSON array only. No prose before or after.
> `[{"text": "...", "rationale": "..."}, ...]`

## Phase 3 — Deepen system prompt (per Agent call)

> You are in FOCUS mode. Take one promising idea and connect
> dots. Sketch how it would actually work in 4 to 8 sentences.
> Name the load-bearing risk. Name the first concrete step a
> coder would take. Then generate 3 to 5 sub-ideas that branch
> off (variations, combinations with other domains, things this
> unlocks). Output JSON only.

Its user prompt includes **sibling ideas** from Phase 1 as a recombination pool, but not any
other deepen branch's output (SKILL.md's Isolation invariant section).

## 3-axis scoring rubric — full mechanics

Formula (port from upstream `engine.ts:135-137`):

```
total = novelty * 0.35 + viability * 0.40 + fit * 0.25
```

**Why viability is heaviest:** a brilliant unshippable idea is the dominant failure mode —
viability is the gatekeeper, novelty is the reason we're here, fit is the tie-breaker.

**`trap` mechanics:** the score pass attaches `trap: "<one-line reason>"` to ideas that look
attractive but have a hidden cost. Trapped ideas are EXCLUDED from the top-K shortlist but
REPORTED separately so the user sees why — a machine-claim ("3 traps, 1 unscalable, 1
premature abstraction, 1 false economy") plus the one-line reasons, not a silent
`if (total < 5) drop` heuristic.

**Score chip rendering:** show as `[N7 V8 F9]` next to each idea in the Wide set.

Source: `provenance.md`'s "3-axis scoring rubric source" section.

## Critic invocation (auto-fire path)

Collect the Phase 1 `ideas[]` JSON and invoke `ideate-critic` per its Input Contract
(`agents/ideate-critic.md`); render the output shape from its returned `scores`, `clusters`,
`shortlist`, `shortlistReasons`, `nonObviousPick`, `nonObviousPickReason`, `runnerUp`,
`confidence`, `traps`, `deepened`, `provocation`. Deepen still runs as 3 parallel Agent
calls, using the critic's `shortlist`.

## Output shape — full rendering contract

Render in this order after Phase 2 — don't collapse into a wall of prose; the structure is
the point.

1. **Brief + cost estimate.** 1-2 lines on the problem/reframe, then:
   *"Cost estimate: ~8–10 Agent calls, ~3k–8k input tokens, ~1k–3k output
   tokens. Actuals vary by problem size."* Advisory heuristic, not a metered
   bill.
2. **Wide set.** Full pool grouped by cluster and angle, one short phrase
   per idea, score chips like `[N7 V8 F9]`. If the critic ran, render its
   `frameCount` next to any cluster ≥3 ("3 frames converged here") — same
   note the host-inline path gives; don't drop it.
3. **Converge.** A 2-4 idea shortlist with a stated reason each — the
   critic's `shortlistReasons` verbatim when it ran, else stated directly.
   Mark the non-obvious-but-viable pick with ★ (`nonObviousPickReason` when
   present). Show `confidence` beside the shortlist if supplied. Name
   `runnerUp` in one line if non-null; omit if `null` — don't fabricate one.
   List traps separately with their one-line reasons.
4. **Focus.** The 3 deepened branches: sketch, load-bearing risk, first
   concrete step, child ideas.
5. **Provocation.** One wildcard question/idea for if nothing landed:
   *"What if we took this seriously: {highest-novelty survivor}"*

Source: `provenance.md`'s "Output-shape source" section.
