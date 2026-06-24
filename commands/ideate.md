---
name: ideate
description: "Parallel divergent ideation. Use when prompts are open-ended (design, architecture, naming, API/SDK, fuzzy-debug) AND high-stakes AND open phrasing — or when the user explicitly types /ideate, asks to brainstorm, or says 'ระดมความคิด', 'brainstorm', 'คิดไอเดีย'. Spawns 5 isolated agent calls under rotating cognitive frames (15-frame pool, 5 per run), scores on novelty/viability/fit, prunes traps, deepens top 3, with a fresh-context critic option. Don't use for syntax, lookups, known-root-cause bugs, or closed phrasing ('quick', 'standard', 'canonical', 'textbook')."
argument-hint: Problem statement to ideate on
disable-model-invocation: false
disable-model-invocation-reason: Auto-fire on vague open-ended prompts is the load-bearing use case (catches prompts the model would otherwise default on). Cost is bounded by the F8.5 cap (orchestrate SKILL §F8.5) and the 2-wave fan-out callout in this command's body — NOT by this flag.
---

# Ideate

Single kbg ideation surface. The user can type `/ideate` explicitly, or the model can auto-route here on vague, open-ended, high-stakes prompts. Either path runs the same algorithm.

## Usage

```
/ideate How should we design a feature flag service?
/ideate What naming convention should we use for our event schemas?
/ideate We're seeing flaky CI; brainstorm root causes we haven't considered.
```

## Pre-flight gate

This surface is expensive. About 8 to 10 Agent calls, 30 to 90 seconds wall clock, 5 to 10x a single answer. Do not pay that cost when a direct answer is better. Run this gate before Phase 1.

**Step 0. Cost + convergence warning check.**

If the session context contains a block of the form `<ideate-budget status="warning" ...>`, the daily ideate threshold has been crossed. If it contains `<ideate-convergence status="warning" ...>`, recent ideate runs on similar problems are converging (same shape, same frames). In either case, **do not auto-fire ideate from Step 2 below**; let the self-judge gate abort and answer directly. If Step 1 matches (the user explicitly invoked `/ideate` or asked for ideate mode), still proceed to Phase 1, but surface the warning in the brief.

**Step 1. Explicit invocation check.**

If the user typed `/ideate` or explicitly asked for "ideate mode", "use the ideate skill", "run ideate on this", or "brainstorm", **SKIP the rest of this section and go straight to Phase 1**. The user opted in. Do not second-guess.

**Step 2. Self-judge (only if Step 1 did not match).**

Ask three questions. If any answer is NO, ABORT.

1. **Open-ended?** Would a senior engineer give multiple viable answers here, or is there one canonical answer? If canonical — syntax fix, known-root-cause bug, lookup, "what is the X for Y" — abort.
2. **High-stakes?** Is the cost of the obvious answer being wrong actually high? Architecture, public API, naming, schema, fuzzy-debug = yes. Side project at 11pm = no.
3. **Open phrasing?** Did the user avoid words like "quick", "standard", "canonical", "textbook", "just", "one-line"? If they used any of those, they want the direct answer. Abort.

If all three pass, proceed to Phase 1.

If any fails, ABORT and answer the question directly. Optionally append one sentence: *"If you want a wider exploration under parallel cognitive frames with explicit trap detection, run `/ideate <your problem>`."*


## Session frame rotation (advisory)

A SessionStart hook emits a block of the form:

```markdown
<ideate-rotation index="N">
- hardware-eyes
- regulator
- ...
</ideate-rotation>
```

**If this block is present in the session context, prefer these 5
frames for the next ideate run.** The hook has already satisfied the
1-wild minimum and rotated the set relative to prior sessions, so
re-running ideate on a similar problem yields different vantages.

If the block is absent (fresh install, hook disabled, or malformed),
fall back to the deterministic picker in
[Picking frames](#picking-frames).

## Convergence warning (advisory)

A SessionEnd hook (`ideate-convergence-capture.sh`) computes a local
embedding for each ideate problem via the Ollama API (`all-minilm:latest` by
default) and stores it in `~/.claude/state/ideate-embeddings.jsonl`. If
today's runs on similar problems have cosine similarity ≥ 0.85, the next
session's `<ideate-convergence status="warning">` block warns that the same
problem is being ideated repeatedly without new vantages.

The default model is `all-minilm:latest`; override with
`KBG_IDEATE_EMBEDDING_MODEL`, and the Ollama host with
`KBG_IDEATE_OLLAMA_HOST`. If Ollama is not running or the model is absent,
the hook silently degrades to `convergence_status=unknown`.

This is a heuristic, not a quality judgment. Query the history with:

```bash
python3 "${KBG_PLUGIN_ROOT}/scripts/ideate-convergence.py" --today
```

## Ideate memory search (user command)

A separate SessionEnd hook (`ideate-memory-capture.sh`) persists the problem
and final output of every `/ideate` run as a markdown file under
`~/.claude/state/ideate-memory/`. A qmd collection indexes those files, so the
user can search past ideate runs with:

```
/ideate-search caching
/ideate-search หาไอเดียที่เคยคิดเรื่อง caching
```

This is a read-only, local-memory feature. It does not influence the
ideation algorithm; it only makes prior runs recallable. The companion script
`${KBG_PLUGIN_ROOT}/scripts/ideate-memory.py` owns `init`, `capture`, `index`, `search`, and
`status`.

## 2-wave fan-out (load-bearing)

> **WARNING — this skill is 2 fan-out waves, NOT 1.**
>
> - **Phase 1 (Diverge)**: 5 parallel Agent calls, peak 5.
> - **Phase 2 (Focus)**: sequential score + cluster on the host
>   (no fan-out).
> - **Phase 3 (Deepen)**: 3 parallel Agent calls, peak 3.
>
> **Peak concurrent = 5** (at the F8.5 hard cap per
> `skills/orchestrate/SKILL.md:420-427`). The 2 waves are
> sequential: Phase 1 → Phase 2 → Phase 3. Total Agent calls per
> run ≈ 8 to 10. **Do not collapse into 1 wave.**
>
> The 2026-06-12 audit caught a 44→105-agent failure mode where a
> soft cap on a work-list was silently doubled by an audit + verify
> layer (see `memory/bounded-agent-spawning.md` and
> `memory/whole-repo-dig-2026-06-16.md`). The regression fixture
> `eval/regressions/ideate-fanout-cap.json` (PR2) locks this
> 2-wave structure in place — the fixture fails if either wave
> is collapsed or if the peak concurrent exceeds 5.

## Phase 1 — Diverge

For the problem P:

1. **Pick 5 cognitive frames** from the [Frames table](#frames-table)
   below. Bias toward `code` or `design` tags when the problem is
   code-shaped. Always include at least one `wild`-tagged frame to
   keep range.
2. **Spawn 5 parallel Agent calls.** One per frame. Each Agent gets
   ONLY:
   - the problem P
   - any context the user provided
   - the chosen frame's vantage prompt
   - a system instruction that forbids evaluation

   The exact user-prompt payload to give each Agent (DO NOT add
   peer branch output — see [Isolation invariant](#isolation-invariant)):

   ```
   PROBLEM:
   {problem}

   {context ? `CONTEXT:\n${context}\n\n` : ""}FRAME — {frame.label}:
   {frame.prompt}

   Generate {ideasPerFrame} ideas under this frame.
   Output JSON array only. No prose before or after.
   [{"text": "...", "rationale": "..."}, ...]
   ```

   The system prompt to attach to each Agent call:

   > You are in DIVERGENT mode. You are a generator, not a critic.
   > Generate 6 short distinct ideas under this frame. Each idea is
   > one phrase or one sentence. Do not evaluate. Do not rank. Do
   > not hedge. The first three obvious answers everyone would
   > give are banned. Push past them into the awkward middle.
   > Output a JSON array only. No prose before or after.
   > `[{"text": "...", "rationale": "..."}, ...]`

3. **Wait for all 5 to return** before reading the outputs. Do not
   start reading one branch before the others are done.

Source for the algorithm shape: upstream
`/tmp/adhd-repo/skills/adhd/SKILL.md:47-82` and
`/tmp/adhd-repo/src/engine.ts:28-36, 61-101`. The
`docs/research/kbg-vs-adhd.md`
doc records the port decisions (deterministic frame pick replacing
`Math.random()`, no zod, parse-failure surface-not-swallow).

## Phase 2 — Focus

After all 5 Diverge branches return:

1. **Score.** Rate each idea on three axes 0 to 10:
   - **Novelty** — distance from the obvious default
   - **Viability** — could it actually ship
   - **Fit** — does it address the stated problem

   For any idea that looks attractive but is a trap (hidden cost,
   false economy, will-not-scale, premature abstraction), attach
   a one-line `trap` reason. `trap` is a free-text reason field,
   NOT a score threshold (see
   [3-axis scoring rubric](#3-axis-scoring-rubric)).

2. **Cluster.** Group ideas into 3 to 6 clusters by their
   **underlying angle**, not by surface keywords. Label clusters
   by angle: "remove-the-server plays", "cache-shaped plays",
   "batched-window plays", "race-multiple-backends plays". The
   shape of the idea space is the point — clusters are how the
   human reader sees the shape.

3. **Deepen the top 3.** Rank by the weighted score
   (`novelty × 0.35 + viability × 0.40 + fit × 0.25`), exclude
   traps, take top 3. For each, spawn one **parallel** Agent call
   (Phase 3) that produces:
   - a 4 to 8 sentence sketch of how the idea works
   - the load-bearing risk
   - the first concrete step a builder would take
   - 3 to 5 child ideas (variations, hybrids, unlocks)

   Deepen Agent instruction (system prompt):

   > You are in FOCUS mode. Take one promising idea and connect
   > dots. Sketch how it would actually work in 4 to 8 sentences.
   > Name the load-bearing risk. Name the first concrete step a
   > coder would take. Then generate 3 to 5 sub-ideas that branch
   > off (variations, combinations with other domains, things this
   > unlocks). Output JSON only.

   The deepen Agent's user prompt includes the **sibling ideas**
   from Phase 1 as a recombination pool, but NOT any other deepen
   branch's output. See
   [Isolation invariant](#isolation-invariant).

**Fresh-context critic option (recommended for high-stakes runs).**
By default Phase 2 + 3 run on the host Claude. That is the same
model class as the generators, which carries the
LLM-judge-circularity caveat documented in `CLAUDE.md`
§"LLM-judge-circularity". For runs where the cost of a blind spot
is high, re-point the critic pass at the `ideate-critic` agent
(`agents/ideate-critic.md`). It uses the same scoring rubric but
starts from a fresh context, reducing the chance that the host
Claude's own generation anchors the judgment. Output is still
**advisory evidence**, not ground truth; the user remains the
gate. See METHODOLOGY.md:74 on "the implementer agreeing with
its own work."

To use the critic agent, collect the Phase 1 `ideas[]` JSON and
invoke `ideate-critic` with the Input Contract in
`agents/ideate-critic.md`. Use its returned `scores`, `clusters`,
`shortlist`, `nonObviousPick`, `traps`, `deepened`, and
`provocation` to render the final output shape below. The
deepen pass can still run as 3 parallel Agent calls on the host,
using the critic's `shortlist` as input.

Source: upstream `/tmp/adhd-repo/skills/adhd/SKILL.md:84-112` and
`/tmp/adhd-repo/src/engine.ts:103-175, 177-229`.

## Frames table

Pick 5 per run. The 15 cognitive frames — each with its tags
(`code`/`design`/`general`/`wild`) and vantage prompt — live in
[`ideate/references/frames.md`](ideate/references/frames.md), kept out of this file to stay
under the command size budget. Bias toward `code`/`design` tags for
code-shaped problems; always include ≥1 `wild` frame for range.

### Picking frames

For code-shaped problems: pick 4 frames tagged `code` or `design`, plus 1
tagged `wild`. For open product or strategy problems: a mix from all tags.
Vary the picks across sessions so the same problem produces different
candidate sets when re-run.

## 3-axis scoring rubric

Exact formula (port from upstream `engine.ts:135-137`):

```
total = novelty * 0.35 + viability * 0.40 + fit * 0.25
```

**Why viability is the heaviest weight:** a brilliant
unshippable idea is the dominant failure mode. Viability is the
gatekeeper, novelty is the reason we're here, fit is the
tie-breaker. Source: `/tmp/adhd-repo/src/engine.ts:103-147`.

**Trap is a free-text reason field, NOT a score threshold.**
The score pass attaches `trap: "<one-line reason>"` for ideas
that look attractive but have a hidden cost. Trapped ideas are
EXCLUDED from the top-K shortlist but REPORTED separately so the
user can see WHY they were pruned. This is the upstream
"shortlist vs traps" split at `engine.ts:275-280` and the
reason Verifier 1 claim A stays honest: the user gets a
machine-claim ("3 traps, 1 unscalable, 1 premature abstraction,
1 false economy") and the underlying one-line reasons, not a
silent `if (total < 5) drop` heuristic.

**Score chip rendering:** show as `[N7 V8 F9]` next to each
idea in the Wide set, so the human reader can compare at a
glance.

## Isolation invariant

**Diverge branches MUST NOT see each other's output. Each Agent
call is independent.** The `userPrompt` payload is

```
PROBLEM + CONTEXT + FRAME.label + FRAME.prompt + "Generate N ideas..."
```

It does NOT list other branches, does NOT carry peer `Idea`
objects, and the system prompt forbids cross-talk. Sibling
recombination is passed ONLY at Phase 3 (deepen), not during
Diverge.

This is the load-bearing property of the algorithm. If a branch
sees another branch's output, the two branches anchor on each
other and the whole method collapses to a wider single thought —
the upstream `engine.ts:251-258` parallel `Promise.all` over a
frame list with no shared state is what preserves it. The
kbg-native parallel pattern (see
`skills/orchestrate/SKILL.md` §F8.5, and the 7-agent-pattern's
"Rule: each file is owned by exactly one agent") generalises the
same invariant: no shared mutable state across parallel branches.

**Practical rules:**

- DO NOT call one Diverge Agent from another.
- DO NOT include a "here's what the other branches generated"
  line in any Diverge userPrompt.
- DO NOT carry `Idea` objects from Phase 1 forward into a Phase
  1 sibling.
- DO pass siblings as a recombination pool to the Phase 3
  deepen Agent (it is the "connect the dots" pass — that is its
  job). Sibling context is *read-only* inside the deepen
  Agent; it is not the focus idea.

## Phase 4 — Interactive deepen (optional)

If the user replies after the initial ideate output with a follow-up
that asks to explore one of the shortlisted ideas, rotate the frames, or
combine candidates, run a short Phase 4 pass instead of starting over.

Supported follow-ups:

1. **"Deepen #2"** or **"Tell me more about the second shortlist idea"**
   → Re-run Phase 3 (Deepen) on just that idea, with the same sibling
   recombination pool, and return a fresh sketch + risk + first step.
2. **"Re-run with frames X, Y, Z"** → Replace the rotated/default frame
   set with the user's explicit picks and run Phase 1 → Phase 3 again.
   Still cap at 5 frames and 2 waves.
3. **"Combine A and B"** (where A and B are idea texts or numbers from
   the wide set) → Spawn one Agent call under the `remove-assumption`
   frame to force a hybrid, then one deepen Agent call on the result.

Phase 4 is **opt-in**. Do not offer it unprompted. It consumes the same
budget envelope as a partial ideate run (1–3 Agent calls), so if the
daily-budget or convergence warning is active, ask the user whether they
want to continue before spawning agents.

## Output shape

After Phase 2, render in this order. Do not collapse it into a
wall of prose. The structure is the point.

1. **Brief + cost estimate.** One or two lines confirming the
   problem and any reframe used, followed by a cost estimate line:
   *"Cost estimate: ~8–10 Agent calls, ~3k–8k input tokens, ~1k–3k
   output tokens. Actuals vary by problem size."* This is an
   advisory heuristic, not a metered bill. The estimate reminds the
   operator that ideate is intentionally expensive.
2. **Wide set.** Full pool grouped by cluster. Each cluster
   labeled by underlying angle. Each idea is one short phrase.
   Show score chips like `[N7 V8 F9]` next to each.
3. **Converge.** A 2 to 4 idea shortlist. State why each is on
   the list. Mark the non-obvious-but-viable pick explicitly
   with ★. List traps separately, each with the one-line reason
   it is a trap.
4. **Focus.** The 3 deepened branches. For each: the sketch, the
   load-bearing risk, the first concrete step, and the child
   ideas.
5. **Provocation.** One wildcard question or idea that opens a
   new direction the user can push into if nothing landed.
   Format: *"What if we took this seriously: {highest-novelty
   survivor}"* — drawn from `engine.ts:307-312`.

Source: upstream `/tmp/adhd-repo/skills/adhd/SKILL.md:145-157`.

## When NOT to use

- **Close-ended tasks** — anything with one correct answer
  (syntax fix, name lookup, "what's the command for X",
  known-root-cause bug).
- **Lookups** — "find the file that does X", "what does Y do",
  "is Z in the codebase".
- **Bug fixes with a known root cause** — fix the bug, don't
  ideate around it.
- **Anything the user wants fast** — "quick", "just", "one-liner",
  "standard", "canonical", "textbook". These are explicit abort
  signals in the pre-flight gate.

If in doubt, answer directly and append a one-sentence upsell
to `/ideate`. The pre-flight gate is cheaper than a wasted
fan-out.

## Anti-patterns

These are how this skill goes wrong. Watch for them.

- **Convergence disguised as divergence.** Ten minor variations
  of one idea is not breadth. If every candidate shares the same
  underlying assumption, you have not diverged. You have
  decorated. Spread the frame picks.
- **Weird-for-weird's-sake with no convergence.** A pile of 30
  unsorted absurdities is as useless as one safe answer. Always
  converge with a real opinion.
- **Walls of equally-weighted prose.** Cluster, label, pull out
  the best. The output structure is half the value.
- **Refusing to commit.** After diverging, take a position on
  what is actually promising. "Here are 30 ideas, you decide" is
  a cop-out. Generate wide, but converge with a real opinion.
- **Skipping the isolation invariant.** If you simulate parallel
  branches by writing them sequentially in one context, you have
  not done ideate. You have done a wider single thought. The
  Agent/Task tool gives each branch a fresh context. Use it.
- **Collapsing Phase 1 + Phase 3 into one wave.** The 2-wave
  structure is a code contract, not a vibe. See
  [2-wave fan-out (load-bearing)](#2-wave-fan-out-load-bearing).
  A single-wave variant breaks the F8.5 cap accounting and is
  flagged by `eval/regressions/ideate-fanout-cap.json` (PR2).
- **Silent parse failures.** If a Diverge branch returns empty
  or unparseable, surface the failure to the user — do not
  pretend the run succeeded. The upstream `engine.ts:88-91`
  silent-empty return is *not* the kbg posture; see
  `agents/silent-failure-hunter.md` and the
  [3-axis scoring rubric](#3-axis-scoring-rubric) note on
  `trap` being a free-text reason field rather than a silent
  drop.
- **Same-model judge treated as ground truth.** Phase 2 + 3
  scoring on the host Claude is the same model class as the
  generators. Treat it as advisory evidence, not ground truth —
  the user is the gate. See [Phase 2 — Focus](#phase-2--focus)
  and CLAUDE.md §"LLM-judge circularity".

## Cost

≈ 8 to 10 Agent calls per run (5 diverge + 1 score + 1 cluster +
3 deepen, with score + cluster on the host). About 5 to 10x a
single-shot answer. The brief includes an advisory cost-estimate line
so the operator sees the token envelope up front. Not for every
keystroke. For decision points where the cost of the obvious answer is
high.

Source: upstream `/tmp/adhd-repo/skills/adhd/SKILL.md:192-194`.

## Cross-references

- **Why this exists** — `docs/research/kbg-vs-adhd.md`
  records the port decisions, the eval-rigor limitation (n=1
  upstream), and the things explicitly rejected.
- **F8.5 hard cap (load-bearing)** —
  `skills/orchestrate/SKILL.md:420-427`
  sets the peak-concurrent cap at 5 agents per wave. The 2-wave
  structure in this skill is engineered to fit that cap exactly.
- **Fresh-context critic pattern** —
  `agents/inferential-structural-judge.md`
  is the kbg-native precedent for the same-model-critic-circularity
  caveat. Score + cluster + deepen are engineered to be
  re-pointable at a fresh-context critic.
- **Methodology on maker ≠ checker** —
  `METHODOLOGY.md:74` — the implementer
  agreeing with its own work is not proof; the verifying agent
  must be given fresh context.
- **Bounded-agent-spawning precedent** —
  `memory/bounded-agent-spawning.md`
  — the 2026-06-12 44→105-agent failure mode this skill's 2-wave
  cap is designed to prevent.
- **Regression fixture (PR2)** —
  `eval/regressions/ideate-fanout-cap.json` locks the 2-wave
  structure + the peak-5 cap. PR1 ships the contract; PR2 ships
  the fixture.
- **Eval rigor limitation (explicit)** — this skill ports
  faithfully from an n=1 upstream demo. The
  `docs/research/kbg-vs-adhd.md`
  §"Eval rigor limitation" section is the load-bearing
  disclaimer: treat this as a structured brainstorming tool, not
  a quality-validated generator.
