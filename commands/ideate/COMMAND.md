---
name: ideate
description: "Parallel divergent ideation (5 isolated agents, rotating frames, novelty/viability/fit scoring). Say 'brainstorm/ระดมความคิด/คิดไอเดีย'. Don't use for syntax, lookups, or closed-phrasing asks."
argument-hint: Problem statement to ideate on
disable-model-invocation: false
disable-model-invocation-reason: Auto-fire on vague prompts is load-bearing (catches prompts the model would otherwise default on). Cost is bounded by the F8.5 cap (orchestrate SKILL §F8.5) and the 2-wave fan-out callout below — NOT by this flag.
model: inherit
effort: high
---

# Ideate

Single kbg ideation surface. Type `/ideate` explicitly, or let the model auto-route here on vague, open-ended, high-stakes prompts — either path runs the same algorithm.

## Usage

```
/ideate How should we design a feature flag service?
/ideate We're seeing flaky CI; brainstorm root causes we haven't considered.
```

## Pre-flight gate

This surface is expensive — about 8-10 Agent calls, 30-90s wall clock,
5-10x a single answer — so don't pay that cost when a direct answer is
better. Run this gate before Phase 1.

**Step 0. Cost + convergence warning check.**

An `<ideate-budget status="warning">` block means the daily threshold is
crossed; an `<ideate-convergence status="warning">` block means recent runs
on similar problems are converging (same shape, same frames). Either one:
**don't auto-fire from Step 2**; let the self-judge gate abort and answer
directly. If Step 1 matches (explicit `/ideate`), still proceed to Phase 1
but surface the warning in the brief. (kbg ships no producer for
`<ideate-budget>` currently: `hooks/session/` has no ideate-related hook and
`hooks.json` has no ideate entry — check for one before relying on Step 0
seeing it, same caveat as `<ideate-convergence>` below.)

**Step 1. Explicit invocation check.**

If the user typed `/ideate` or asked for "ideate mode"/"use the ideate
skill"/"run ideate on this"/"brainstorm", **skip the rest of this section
and go straight to Phase 1** — they opted in, don't second-guess.

**Step 2. Self-judge (only if Step 1 did not match).**

Ask three questions. If any answer is NO, ABORT.

1. **Open-ended?** Multiple viable answers, or one canonical (syntax fix,
   known-root-cause bug, lookup, "what is the X for Y") → abort.
2. **High-stakes?** Is the obvious answer expensive to get wrong
   (architecture, public API, naming, schema, fuzzy-debug = yes; side
   project at 11pm = no)?
3. **Open phrasing?** Did the user avoid "quick"/"standard"/"canonical"/
   "textbook"/"just"/"one-line"? Any of those → they want the direct
   answer, abort.

All three pass → proceed to Phase 1. Any fails → ABORT and answer directly,
optionally appending: *"If you want a wider exploration under parallel
cognitive frames with explicit trap detection, run `/ideate <your problem>`."*

## Session frame rotation, convergence, and memory search (advisory)

A SessionStart hook may inject `<ideate-rotation index="N">` with 5 frame
names — prefer those (already covers the 1-wild minimum, rotated vs. prior
sessions). If absent, fall back to [Picking frames](#picking-frames).

Step 0 already honours an `<ideate-convergence status="warning">` block;
its capture side (SessionEnd embedding hook + `convergence.sh`) is **not
currently wired** (removed in the reset) — treat convergence as
advisory-only until rebuilt.

Past runs are searchable via `/ideate-search <query>` (Thai OK), backed by
the `ideate-memory` qmd collection — read-only, doesn't affect the
algorithm, only makes runs recallable. Its capture hook is also not wired;
search only returns runs captured other ways until rebuilt. Mechanics:
`references/provenance.md` §"Advisory hooks — full mechanics".

## 2-wave fan-out (load-bearing)

> **WARNING — this skill is 2 fan-out waves, NOT 1.**
>
> - **Phase 1 (Diverge)**: 5 parallel Agent calls, peak 5.
> - **Phase 2 (Focus)**: sequential score + cluster on the host, no fan-out.
> - **Phase 3 (Deepen)**: 3 parallel Agent calls, peak 3.
>
> **Peak concurrent = 5** (the F8.5 hard cap, `skills/orchestrate/SKILL.md`
> §"Bounded fan-out — hard cap (F8.5)"). Sequential: Phase 1 → Phase 2 →
> Phase 3. ≈8-10 Agent calls/run. **Do not collapse into 1 wave.**
>
> Audit history (the 44→105-agent failure mode) and enforcement mechanism:
> `references/provenance.md` §"2-wave fan-out — audit history".

## Phase 1 — Diverge

For the problem P:

1. **Pick 5 cognitive frames** — see [Picking frames](#picking-frames).
2. **Spawn 5 parallel Agent calls**, one per frame — each Agent gets ONLY
   the payload and system prompt below, no peer branch data (see
   [Isolation invariant](#isolation-invariant)):

   ```
   PROBLEM:
   {problem}

   {context ? `CONTEXT:\n${context}\n\n` : ""}FRAME — {frame.label}:
   {frame.prompt}

   Generate {ideasPerFrame} ideas under this frame.
   Output JSON array only. No prose before or after.
   [{"text": "...", "rationale": "..."}, ...]
   ```

   System prompt for each call:

   > You are in DIVERGENT mode. You are a generator, not a critic.
   > Generate 6 short distinct ideas under this frame. Each idea is
   > one phrase or one sentence. Do not evaluate. Do not rank. Do
   > not hedge. The first three obvious answers everyone would
   > give are banned. Push past them into the awkward middle.
   > Output a JSON array only. No prose before or after.
   > `[{"text": "...", "rationale": "..."}, ...]`

3. **Wait for all 5 to return** before reading outputs — don't start
   reading one branch before the others finish.

Algorithm-shape source + port decisions: `references/provenance.md` §"Phase 1 algorithm-shape source".

## Phase 2 — Focus

After all 5 Diverge branches return:

1. **Score.** Rate each idea on three axes 0 to 10:
   - **Novelty** — distance from the obvious default
   - **Viability** — could it actually ship
   - **Fit** — does it address the stated problem

   Attach a one-line `trap` reason to any idea that looks attractive but is
   a trap (hidden cost, false economy, will-not-scale, premature
   abstraction) — `trap` is a free-text reason field, NOT a score threshold
   (see [3-axis scoring rubric](#3-axis-scoring-rubric)).

   **Named bias guard (anchoring + confirmation):** score every idea on the
   same axes before ranking — don't let the first idea set the scale.
   `trap` is the confirmation guard: look for why an attractive idea is
   wrong, not just evidence it's right.

2. **Cluster.** Group ideas into 3-6 clusters by **underlying angle**, not
   surface keywords — label by angle ("remove-the-server plays",
   "cache-shaped plays", "batched-window plays", "race-multiple-backends
   plays"). The shape of the idea space is the point.

   **Note independent convergence:** when a cluster draws from ≥3 distinct
   frames, say so next to the label ("3 frames converged here") — keep it
   visible, don't fold it in silently.

3. **Deepen the top 3.** Rank by weighted score (`novelty × 0.35 +
   viability × 0.40 + fit × 0.25`), exclude traps, take top 3. Spawn one
   **parallel** Agent call per idea (Phase 3) — see the system prompt below
   for exactly what it produces.

   System prompt:

   > You are in FOCUS mode. Take one promising idea and connect
   > dots. Sketch how it would actually work in 4 to 8 sentences.
   > Name the load-bearing risk. Name the first concrete step a
   > coder would take. Then generate 3 to 5 sub-ideas that branch
   > off (variations, combinations with other domains, things this
   > unlocks). Output JSON only.

   Its user prompt includes **sibling ideas** from Phase 1 as a
   recombination pool, but not any other deepen branch's output (see
   [Isolation invariant](#isolation-invariant)).

**Fresh-context critic — default on the auto-fire path.** Host-Claude
scoring carries an LLM-judge-circularity caveat; Step 2 already requires a
YES on "high-stakes?" before auto-fire, so:

- **Auto-fired (via Step 2):** default to the `ideate-critic` agent
  (`agents/ideate-critic.md`), not host-Claude.
- **Explicit invocation (via Step 1, self-judge skipped):** keep host-Claude
  as default — stakes aren't classified here; the user can request the
  critic explicitly.

**To use it:** collect the Phase 1 `ideas[]` JSON and invoke `ideate-critic`
per its Input Contract (`agents/ideate-critic.md`); render the output shape
below from its returned `scores`, `clusters`, `shortlist`,
`shortlistReasons`, `nonObviousPick`, `nonObviousPickReason`, `runnerUp`,
`confidence`, `traps`, `deepened`, `provocation`. Deepen still runs as 3
parallel Agent calls, using the critic's `shortlist`.

Full rationale: `references/provenance.md` §"Phase 2 critic-routing source".

## Frames table

The 15 cognitive frames — each with its tags (`code`/`design`/`general`/
`wild`) and vantage prompt — live in
[`references/frames.md`](references/frames.md), kept out of this file for
size.

### Picking frames

Code-shaped problems: pick 4 frames tagged `code` or `design`, plus 1
tagged `wild`. Open product/strategy problems: a mix from all tags. Vary
picks across sessions so re-runs produce different candidates.

## 3-axis scoring rubric

Formula (port from upstream `engine.ts:135-137`):

```
total = novelty * 0.35 + viability * 0.40 + fit * 0.25
```

**Why viability is heaviest:** a brilliant unshippable idea is the dominant
failure mode — viability is the gatekeeper, novelty is the reason we're
here, fit is the tie-breaker.

**`trap` mechanics:** the score pass attaches `trap: "<one-line reason>"` to
ideas that look attractive but have a hidden cost. Trapped ideas are EXCLUDED from the top-K shortlist but
REPORTED separately so the user sees why — a machine-claim ("3 traps, 1
unscalable, 1 premature abstraction, 1 false economy") plus the one-line
reasons, not a silent `if (total < 5) drop` heuristic.

**Score chip rendering:** show as `[N7 V8 F9]` next to each idea in the Wide set.

Source: `references/provenance.md` §"3-axis scoring rubric source".

## Isolation invariant

**Diverge branches MUST NOT see each other's output — each Agent call is
independent.** The Phase 1 payload does NOT list other branches or carry
peer `Idea` objects, and its system prompt forbids cross-talk. Sibling
recombination is passed ONLY at Phase 3 (deepen), never during Diverge.

This is load-bearing: a branch seeing another's output anchors the two
together, collapsing the method to one wider thought. The kbg-native
pattern generalises this: no shared mutable state across parallel branches
(`skills/orchestrate/SKILL.md` §F8.5; the 7-agent-pattern's "each file
owned by exactly one agent" rule).

**Practical rules:** don't call one Diverge Agent from another; don't
include a "here's what the other branches generated" line in any Diverge
userPrompt; don't carry `Idea` objects forward into a Phase 1 sibling. DO
pass siblings as a read-only recombination pool to the Phase 3 deepen Agent
— never the focus idea.

Source: `references/provenance.md` §"Isolation invariant source".

## Phase 4 — Interactive deepen (optional)

If the user replies after the initial output asking to explore a
shortlisted idea, rotate the frames, or combine candidates, run a short
Phase 4 pass instead of starting over. The 3 supported patterns ("Deepen
#2", "Re-run with frames X, Y, Z", "Combine A and B") and the exact
behavior for each: [`references/phase4.md`](references/phase4.md).

Phase 4 is **opt-in** — don't offer it unprompted. It costs the same as a
partial run (1-3 Agent calls); ask first if the budget/convergence warning
is active.

## Output shape

Render in this order after Phase 2 — don't collapse into a wall of prose;
the structure is the point.

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

Source: `references/provenance.md` §"Output-shape source".

## When NOT to use

Concrete triggers for the pre-flight gate's Step 2 abort path: syntax
fixes, name/file lookups ("find the file that does X", "what does Y do",
"is Z in the codebase"), known-root-cause bug fixes ("fix the bug, don't
ideate around it"), and anything phrased "quick"/"just"/"one-liner"/
"standard"/"canonical"/"textbook".

## Anti-patterns

How this skill goes wrong — convergence disguised as divergence, walls of
equally-weighted prose, skipping the isolation invariant, collapsing the
2-wave structure, silent parse failures, same-model-judge-as-ground-truth:
`references/anti-patterns.md`.

## Cost

Per-run Agent-call estimate (≈8-10, ≈9-11 auto-fired) and provenance:
`references/cost.md`.

## Cross-references

Why this exists (`kbg-vs-adhd.md`), the F8.5 cap, the fresh-context critic
pattern, maker≠checker methodology, the bounded-agent-spawning precedent,
and the eval-rigor limitation: `references/provenance.md`
§"Cross-references".
