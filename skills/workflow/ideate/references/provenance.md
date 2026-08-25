# Ideate — Provenance & Cross-References

Upstream algorithm-shape citations, the fan-out cap's audit history, and pointers to related
kbg surfaces — kept out of `SKILL.md` to stay under its size budget.
None of this is needed to execute a run; it's why the design is shaped the way it is.

## 2-wave fan-out — audit history

The 2026-06-12 audit caught a 44→105-agent failure mode where a
soft cap on a work-list was silently doubled by an audit + verify
layer (see `memory/bounded-agent-spawning.md` and
`memory/whole-repo-dig-2026-06-16.md`). There is no eval/regression
fixture for this — `eval/` does not exist in this repo (the eval
dataset gate was deleted, not rebuilt, in the 2026-06-27 reset;
see `CLAUDE.md`'s Validation section). What is actually code-enforced
is narrower than a fixture would claim: the F8.5 hard cap in
`skills/workflow/orchestrate/SKILL.md` clamps any single wave's work-list
to ≤5 before spawning ("the clamp is the JS work-list slice
before `parallel()`/`pipeline()`"). This command's Phase 1 (5)
and Phase 3 (3) sizes are written to sit inside that per-wave
clamp. The "exactly 2 waves, not 3+" shape is this skill's own
design contract (see Phase 1 and Phase 2 — including its Deepen step — in
`SKILL.md`), not
something F8.5 polices — F8.5 caps how big a wave can get, not
how many waves a skill runs.

## Phase 1 algorithm-shape source

Source for the algorithm shape: upstream
`/tmp/adhd-repo/skills/adhd/SKILL.md:47-82` and
`/tmp/adhd-repo/src/engine.ts:28-36, 61-101`. The
`kbg-vs-adhd.md` doc (read via Bash: `cat "${MH_PLUGIN_ROOT}/docs/research/kbg-vs-adhd.md"`)
records the port decisions (deterministic frame pick replacing
`Math.random()`, no zod, parse-failure surface-not-swallow).

## Phase 2 critic-routing source

Source: upstream `/tmp/adhd-repo/skills/adhd/SKILL.md:84-112` and
`/tmp/adhd-repo/src/engine.ts:103-175, 177-229`.

**Full rationale** (compact routing rule lives in `SKILL.md`'s "Phase 2 —
Focus" section):

- Host-Claude scoring (Phase 2+3 run on the same model class as the Phase 1
  generators) carries the LLM-judge-circularity caveat from `CLAUDE.md`'s
  "Why — the unifying crux" (in the Architecture section).
- On the explicit-invocation path (via Step 1, self-judge skipped), stakes
  aren't classified — don't infer high-stakes from prompt wording like
  "critical"/"production"; that lexical-heuristic pattern is exactly what
  `harness-audit` already flags as toothless elsewhere.
- `ideate-critic` reuses the same scoring rubric but starts fresh, cutting
  the chance the host's own generation anchors the judgment. Its output is
  still advisory evidence, not ground truth — the user is the gate
  (CLAUDE.md's Architecture section, "the implementer agreeing with its own work").
- Routing to the critic adds no third fan-out wave: Phase 2 goes from 0
  agent calls (host-inline) to 1 sequential call on the auto-fire path, not
  a parallel spawn — the "2-wave, peak-5" F8.5 contract is unaffected.

## Output-shape source

Source: upstream `/tmp/adhd-repo/skills/adhd/SKILL.md:145-157`. The
Provocation line's format (`"What if we took this seriously: ..."`) is
from `engine.ts:307-312`.

## 3-axis scoring rubric source

Source: `/tmp/adhd-repo/src/engine.ts:103-147` (why viability is the
heaviest weight) and `engine.ts:275-280` (the upstream "shortlist vs traps"
split that the `trap` free-text field ports from).

## Isolation invariant source

The upstream `engine.ts:251-258` parallel `Promise.all` over a frame list
with no shared state is what preserves this property in the original
implementation.

## Cost source

Source: upstream `/tmp/adhd-repo/skills/adhd/SKILL.md:192-194`.

## Advisory hooks — full mechanics

Full detail behind `SKILL.md`'s "Session frame rotation, convergence, and
memory search" section.

**Session frame rotation.** A SessionStart hook emits a block of the form:

```markdown
<ideate-rotation index="N">
- hardware-eyes
- regulator
- ...
</ideate-rotation>
```

If present, prefer these 5 frames for the next ideate run.

**Ideate memory search.** Past `mh:ideate` runs are saved as markdown under
the ideate-memory location and indexed by the `ideate-memory` qmd
collection; `mh:ideate-search` queries that collection directly via the qmd
MCP tool:

```
mh:ideate-search caching
mh:ideate-search หาไอเดียที่เคยคิดเรื่อง caching
```

## Cross-references

- **Why this exists** — `kbg-vs-adhd.md` (read via Bash: `cat "${MH_PLUGIN_ROOT}/docs/research/kbg-vs-adhd.md"`)
  records the port decisions, the eval-rigor limitation (n=1
  upstream), and the things explicitly rejected.
- **F8.5 hard cap (load-bearing)** —
  `skills/workflow/orchestrate/SKILL.md`'s "Bounded fan-out — hard cap
  (F8.5)" section
  sets the peak-concurrent cap at 5 agents per wave, enforced by
  the lead clamping the work-list before spawning. The 2-wave
  structure in this skill is engineered to fit that cap exactly.
- **Fresh-context critic pattern** —
  `agents/ideate-critic.md`
  is the kbg-native critic used for the same-model-critic-circularity
  caveat (see Phase 2 — Focus in `SKILL.md`). Score + cluster +
  deepen are engineered to be re-pointable at this fresh-context
  critic.
- **Methodology on maker ≠ checker** —
  CLAUDE.md's Operating model, under the Architecture section — the implementer
  agreeing with its own work is not proof; the verifying agent
  must be given fresh context.
- **Bounded-agent-spawning precedent** —
  `memory/bounded-agent-spawning.md`
  — the failure mode this skill's 2-wave cap is designed to
  prevent; full narrative + enforcement caveat in the
  "2-wave fan-out — audit history" section above.
  Not backed by a regression fixture — do not cite one that isn't
  built.
- **Eval rigor limitation (explicit)** — this skill ports
  faithfully from an n=1 upstream demo. The
  `kbg-vs-adhd.md`'s "Eval rigor limitation" section (read via Bash: `cat "${MH_PLUGIN_ROOT}/docs/research/kbg-vs-adhd.md"`)
  is the load-bearing
  disclaimer: treat this as a structured brainstorming tool, not
  a quality-validated generator.
