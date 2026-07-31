# Ideate — Provenance & Cross-References

Upstream algorithm-shape citations, the fan-out cap's audit history, and pointers to related
kbg surfaces — kept out of `COMMAND.md` to stay under the SKILL.md-equivalent size budget.
None of this is needed to execute a run; it's why the design is shaped the way it is.

## 2-wave fan-out — audit history

The 2026-06-12 audit caught a 44→105-agent failure mode where a
soft cap on a work-list was silently doubled by an audit + verify
layer (see `memory/bounded-agent-spawning.md` and
`memory/whole-repo-dig-2026-06-16.md`). There is no eval/regression
fixture for this — `eval/` does not exist in this repo (CLAUDE.md:
"eval gate [is] pending rebuild"). What is actually code-enforced
is narrower than a fixture would claim: the F8.5 hard cap in
`skills/orchestrate/SKILL.md` clamps any single wave's work-list
to ≤5 before spawning ("the clamp is the JS work-list slice
before `parallel()`/`pipeline()`"). This command's Phase 1 (5)
and Phase 3 (3) sizes are written to sit inside that per-wave
clamp. The "exactly 2 waves, not 3+" shape is this command's own
design contract (see Phase 1 / Phase 2 / Phase 3 in `COMMAND.md`), not
something F8.5 polices — F8.5 caps how big a wave can get, not
how many waves a skill runs.

## Phase 1 algorithm-shape source

Source for the algorithm shape: upstream
`/tmp/adhd-repo/skills/adhd/SKILL.md:47-82` and
`/tmp/adhd-repo/src/engine.ts:28-36, 61-101`. The
`kbg-vs-adhd.md` doc (read via Bash: `cat "${KBG_PLUGIN_ROOT}/docs/research/kbg-vs-adhd.md"`)
records the port decisions (deterministic frame pick replacing
`Math.random()`, no zod, parse-failure surface-not-swallow).

## Phase 2 critic-routing source

Source: upstream `/tmp/adhd-repo/skills/adhd/SKILL.md:84-112` and
`/tmp/adhd-repo/src/engine.ts:103-175, 177-229`.

## Output-shape source

Source: upstream `/tmp/adhd-repo/skills/adhd/SKILL.md:145-157`.

## Cost source

Source: upstream `/tmp/adhd-repo/skills/adhd/SKILL.md:192-194`.

## Cross-references

- **Why this exists** — `kbg-vs-adhd.md` (read via Bash: `cat "${KBG_PLUGIN_ROOT}/docs/research/kbg-vs-adhd.md"`)
  records the port decisions, the eval-rigor limitation (n=1
  upstream), and the things explicitly rejected.
- **F8.5 hard cap (load-bearing)** —
  `skills/orchestrate/SKILL.md` §"Bounded fan-out — hard cap
  (F8.5)"
  sets the peak-concurrent cap at 5 agents per wave, enforced by
  the lead clamping the work-list before spawning. The 2-wave
  structure in this skill is engineered to fit that cap exactly.
- **Fresh-context critic pattern** —
  `agents/ideate-critic.md`
  is the kbg-native critic used for the same-model-critic-circularity
  caveat (see Phase 2 — Focus in `COMMAND.md`). Score + cluster +
  deepen are engineered to be re-pointable at this fresh-context
  critic.
- **Methodology on maker ≠ checker** —
  CLAUDE.md's Operating model, under §Architecture — the implementer
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
  `kbg-vs-adhd.md` §"Eval rigor limitation" section (read via Bash: `cat "${KBG_PLUGIN_ROOT}/docs/research/kbg-vs-adhd.md"`)
  is the load-bearing
  disclaimer: treat this as a structured brainstorming tool, not
  a quality-validated generator.
