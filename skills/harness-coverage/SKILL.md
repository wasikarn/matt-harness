---
name: harness-coverage
description: "Read-only harness-coverage report: renders the 2x2x3 (12-cell) grid from `hooks/sensors.json` and the governance journal, with a 60% decay threshold and the intentional-gap cell `inf-fb-behaviour` flagged. Use when the operator wants to know which cells are populated, stale, or empty, wants a quarter-end decay measurement, or a 12-row table view of the journal. Don't use for: per-session drill-down or a verdict stream (use `kbg:harness-health`), or per-sensor fire-rate (read the journal)."
---

# Skill: harness-coverage

Read-only rendering layer over `scripts/evals/harness-coverage.py` (the
deterministic 12-cell aggregator shipped in wave 2). The script reads
`hooks/sensors.json` + the governance journal and emits the
2x2x3 coverage grid (Bockeler 2026-04, L356-L374 + L437-L479; the same
model baked into `CLAUDE.md`). This skill is the human-facing surface:
it runs the script and presents the output as a 12-row markdown table
with the 60% decay threshold (per `docs/harness-decay-cadence.md`
DECAY-1) called out cell-by-cell.

The skill is **advisory only**. It never writes to the journal, never
modifies the sensor registry, never emits a blocking or gating
decision of any kind, and is **not** wired into any hook lifecycle.
The 60% highlight is *information*, not a *decision*; the operator
decides what to decommission per the decay-cadence 3-step loop
(diagnose, plan, re-measure).

The skill is the **SKILL-1** deliverable of the `harness-coverage-metric`
plan (`.claude/tasks/harness-coverage-metric.md`). Aggregator = wave 2
(`scripts/evals/harness-coverage.py`, AGG-1); this skill = wave 3; regression
fixture = wave 4 (`eval/regressions/harness-coverage.json`, FIX-1);
decay-cadence wiring = LEAD-D's DECAY-1.

## When to use

- The operator wants a single 12-row markdown table showing the
  current coverage posture of the harness.
- The operator wants to know which cells are `populated` / `stale` /
  `coverage_hole` / `intentional_gap`.
- The operator wants to know which cells are decay candidates (sub-60%
  AND not `intentional_gap`) so they can run the decay-cadence
  diagnose / plan / re-measure loop.
- The operator wants the global rollup line (`populated=N holes=N
  gaps=N score=N% drift_30d=N%`) at the bottom of the table.
- The operator wants JSON for downstream tooling
  (`python3 scripts/evals/harness-coverage.py --format json`).
- The operator wants to confirm that the *known intentional gap* cell
  (`inf-fb-behaviour`) is annotated as such, not scored as 0% decay.

## When NOT to use

- **Per-session forensic drill-down** ("show me the last 10 events for
  sensor X") — use `kbg:harness-health` instead. This skill is the
  *fleet-level* view; `harness-health` is the *journal-history* view.
- **Per-sensor fire-rate investigation** — read the journal directly
  (`jq` + `hooks/JOURNAL-SCHEMA.md`); the coverage metric is a
  30-session aggregate, not a per-event lens.
- **Verdict stream** (a journal query for `inferential-structural`
  verdicts) — use `kbg:harness-health --event-type verdict`.
- **Re-scoring a verdict** — use the `inferential-structural-judge`
  agent directly; the coverage script counts *events*, it does not
  *score* them.
- **Adding a sensor** — this skill *reports* coverage; it does not
  *change* the registry. Add sensors via the
  `sensor-fire-notification` workflow and the
  `hooks/sensors.json` registry hand-edit.
- **Auto-pruning sensors below 60%** — out of scope by design. The
  decay-cadence is human-gated (see `CLAUDE.md` § "The autonomy
  invariant"); the metric informs, it does not decide.

## Cost

- The script runs at human request (no hook fires it; no scheduled
  timer of any kind).
- Wall time: ~50ms on a real journal (the script's own perf claim;
  validated in wave-2 done-when).
- I/O: reads `hooks/sensors.json` (hand-curated registry) + the
  governance journal at `~/.claude/governance-events.jsonl`. The
  script does *not* write to either.
- Tokens: zero. No LLM in the loop. The script is stdlib-only Python.
- Frequency: quarterly per `decay-cadence.md` DECAY-1, plus
  on-demand when the operator adds/removes a sensor.
- No scheduled trigger of any kind. The skill is invoked on operator
  request; it is not driven by an unattended loop or a scheduled
  timer.

## Quick start

```bash
# 12-row markdown table (the default operator view)
python3 scripts/evals/harness-coverage.py --format markdown

# JSON for downstream tooling (eval fixtures, future harness-coverage
# fixture, dashboards)
python3 scripts/evals/harness-coverage.py --format json

# Custom window (default is 30 sessions; the script caps at 180)
python3 scripts/evals/harness-coverage.py --window-sessions 7 --format markdown

# Override journal / sensors path (used by the wave-4 regression fixture)
python3 scripts/evals/harness-coverage.py --journal-path /tmp/j.jsonl --format json
```

## Input Contract

### CLI args (the script's only stable contract)

| Flag | Type | Default | Meaning |
|---|---|---|---|
| `--format` | `json` \| `markdown` | `json` | Output shape. `markdown` is the 12-row table the operator reads; `json` is the §3 schema envelope for downstream tooling. |
| `--window-sessions N` | int | `30` | Rolling window in sessions (capped at 180 by the script; the window is approximated as N days because the journal has no session-id -> wall-clock join table). |
| `--weight-meaningful W` | float | `0.7` | Weight applied to meaningful fires (verdicts with non-null `fields.top_finding`). |
| `--weight-trivial W` | float | `0.3` | Weight applied to trivial fires (verdict = "no findings", or `inferential_structural_verdict_skipped`). |
| `--journal-path PATH` | path | `~/.claude/governance-events.jsonl` | Override journal path. Overridable via `CLAUDE_JOURNAL_PATH` env var per `hooks/JOURNAL-SCHEMA.md` "Test override". |
| `--sensors-path PATH` | path | `hooks/sensors.json` | Override sensor registry path. |

### Read paths

- **Journal** — `~/.claude/governance-events.jsonl` by default
  (overridable via `--journal-path` and `CLAUDE_JOURNAL_PATH`). The
  script reads the nested envelope per `JOURNAL-SCHEMA.md` "Envelope
  (nested)": `{"id", "ts", "session", "hook", "event", "source",
  "fields": {...}}`. The script only filters on `hook`, `event`, `ts`,
  and `fields.score` / `fields.top_finding`; every other top-level
  key is ignored.
- **Sensor registry** — `hooks/sensors.json` by default
  (overridable via `--sensors-path`). Reads the `sensors[]` array
  entries: `name`, `fallback_role`, `max_silent_days`, `enabled`.
- **No write paths.** The skill NEVER appends to the journal,
  NEVER writes to `hooks/sensors.json`, NEVER invokes an LLM, NEVER
  spawns a subprocess to `claude`. The script is stdlib-only Python.

### Failure modes for the CLI

- **No args** → defaults to `--format json`, exit 0. The
  12-row markdown view requires `--format markdown`.
- **Malformed CLI args** → argparse prints usage, exit 2.
- **`--window-sessions 0` or negative** → `error:` to stderr, exit 1.
- **`--weight-meaningful < 0` or `--weight-trivial < 0`** → `error:`
  to stderr, exit 1.
- **`--journal-path PATH` does not exist** → `warning:` to stderr
  (`journal not found at PATH; treating as empty`), exit 0, emits
  a 0% grid with all 12 cells in `stale` status. The known
  intentional-gap cell (`inf-fb-behaviour`) remains annotated.
- **`--sensors-path PATH` does not exist** → `warning:` to stderr
  (`registry not found at PATH; treating as empty`), exit 0, emits
  a 0% grid with all 12 cells in `coverage_hole` status (no sensors
  to map to cells). The known intentional-gap cell remains annotated.
- **Malformed JSONL line** (truncated write, encoding glitch) →
  WARN to stderr with the line number, skip the line, continue.
  The script never crashes on a corrupt journal line — per
  `JOURNAL-SCHEMA.md` "Fail-loud" the *producer* should fail loud,
  but the *consumer* is best-effort.
- **0 events match the window** → exit 0, all 12 cells score 0
  with the `stale` status (or `coverage_hole` if the registry is
  missing). This is a real result, not an error.
- **Empty `hooks/sensors.json`** (zero entries) → exit 0, all 12
  cells in `coverage_hole` status. A freshly-installed harness with
  no registered sensors is a valid state; the operator decides
  whether that is a coverage hole or a fresh install.

## Output Format

Two output shapes, both deterministic (no LLM in the loop).

### Markdown (`--format markdown`)

```text
| cell_id | status | cell_score_pct | drift_pct | intentional_gap |
|---|---|---:|---:|---|
| comp-ff-maintainability | stale | 0 | 0 |  |
| comp-ff-arch-fit | stale | 0 | 0 |  |
| comp-ff-behaviour | stale | 0 | 0 |  |
| comp-fb-maintainability | stale | 0 | 0 |  |
| comp-fb-arch-fit | stale | 0 | 0 |  |
| comp-fb-behaviour | stale | 0 | 0 |  |
| inf-ff-maintainability | stale | 0 | 0 |  |
| inf-ff-arch-fit | stale | 0 | 0 |  |
| inf-ff-behaviour | stale | 0 | 0 |  |
| inf-fb-maintainability | populated | 1095 | 1095 |  |
| inf-fb-arch-fit | populated | 1095 | 1095 |  |
| inf-fb-behaviour | intentional_gap | 0 | 0 | Bockeler L465-L478 names behav...
**Global:** populated=2 holes=0 gaps=1 score=1095% drift_30d=1095%
_window_sessions=30_
```

Columns:

- `cell_id` — the 12-cell id (`{direction}-{axis}`), where
  `direction ∈ {comp-ff, comp-fb, inf-ff, inf-fb}` and
  `axis ∈ {maintainability, arch-fit, behaviour}`.
- `status` — one of `populated`, `stale`, `coverage_hole`,
  `intentional_gap`. See status legend below.
- `cell_score_pct` — the cell's score in the 30-session window
  (weighted fires / expected fires × 100). The score can exceed 100
  if the cell fires more than the expected rate (the script does
  not clamp).
- `drift_pct` — the cell's score change versus the *prior* 30-session
  window (`current - prior`).
- `intentional_gap` — first 60 chars of the rationale string, or
  empty if not an intentional gap.

Status legend:

- `populated` — the cell has registered sensors AND the 30-session
  window has weighted fires ≥ the expected rate. Healthy.
- `stale` — the cell has registered sensors BUT the 30-session
  window is below the expected rate. **Decay candidate** if
  `cell_score_pct < 60%` AND not `intentional_gap` (per
  `decay-cadence.md` DECAY-1).
- `coverage_hole` — the cell has NO registered sensors (the registry
  is empty or no sensor's `fallback_role` maps to this cell). A
  coverage hole is not necessarily a decay candidate — it may be a
  cell the harness has no entry for. The operator decides.
- `intentional_gap` — a known deliberate gap, annotated in the
  script's `KNOWN_INTENTIONAL_GAPS` table. The current
  intentional-gap cell is `inf-fb-behaviour` (Bockeler L465-L478,
  ADR 0002 L112).

Global rollup line (last 2 lines of the markdown output):

- `populated=N holes=N gaps=N score=N% drift_30d=N%`
- `_window_sessions=N_` (echoes the window for the report)

### JSON (`--format json`)

```jsonc
{
  "schema_version": 1,
  "computed_at": "2026-06-15T16:42:36.287Z",
  "window_sessions": 30,
  "grid": [
    {
      "cell_id": "comp-ff-maintainability",
      "direction": "comp-ff",
      "axis": "maintainability",
      "population": { "sensors_listed": 9, "sensors_enabled": 9 },
      "activation": {
        "expected_events_per_window": 30,
        "actual_events_in_window": 0,
        "fires_skipped_budget": 0,
        "fires_skipped_absent": 0
      },
      "verdict_quality": {
        "meaningful_fires": 0,
        "trivial_fires": 0,
        "weight_meaningful": 0.7,
        "weight_trivial": 0.3,
        "weighted_score": 0.0
      },
      "cell_score_pct": 0,
      "drift_vs_prev_window_pct": 0,
      "status": "stale",
      "intentional_gap": null
    }
    /* ... 11 more cells ... */
  ]
}
```

The JSON shape is the §3 schema in
`docs/research/harness-coverage-metric-design.md` (wave-1 deliverable,
DOC-1). It is the contract for downstream tooling and the wave-4
regression fixture (`eval/regressions/harness-coverage.json`).

## Failure Modes

Per the script's design (`scripts/evals/harness-coverage.py` main + the
journal consumer pattern from `hooks/JOURNAL-SCHEMA.md` "Fail-loud"):

| # | Failure | Behavior | Why |
|---|---|---|---|
| 1 | **Journal file missing** | `warning: journal not found at PATH; treating as empty` to stderr, exit 0, all 12 cells in `stale` status, score = 0% | Decay-cadence operator workflow: a missing journal is itself a *valid* state (fresh install), not an error. The 0% grid is a *measurement*, not a failure. |
| 2 | **Registry file missing** | `warning: registry not found at PATH; treating as empty` to stderr, exit 0, all 12 cells in `coverage_hole` status, score = 0% | No sensors → no cell mapping → every cell is a hole. This is a *valid* state for a freshly-installed harness. The operator decides whether to register sensors. |
| 3 | **Malformed JSONL line** (truncated write, encoding glitch) | WARN to stderr with the line number, skip the line, continue | Per `JOURNAL-SCHEMA.md` "Fail-loud" + "the consumer logs+warns every corrupt line with its line number instead of crashing the whole digest." The script honors that contract. |
| 4 | **`--window-sessions 0` or negative** | `error: --window-sessions must be > 0` to stderr, exit 1 | The metric is a 30-session rolling window by design; N=0 is not a meaningful window. |
| 5 | **`--weight-meaningful < 0` or `--weight-trivial < 0`** | `error: weights must be non-negative` to stderr, exit 1 | The weights are non-negative by design; a negative weight is a bug in the operator's flag. |
| 6 | **Malformed CLI args** | argparse prints usage, exit 2 | Standard argparse behavior; the operator fixes the flag. |
| 7 | **No events match the window** (real journal, but no fires in 30 sessions) | exit 0, all 12 cells in `stale` status, score = 0% | "No fires" is a real measurement (e.g. the harness is genuinely inert), not an error. The operator decides whether that is a *decay* (per the 60% threshold) or a *valid idle* state. |
| 8 | **Empty `hooks/sensors.json`** (zero entries) | exit 0, all 12 cells in `coverage_hole` status, score = 0% | A freshly-installed harness with no registered sensors is a valid state. The script does *not* try to recover by re-discovering sensors from `hooks/hooks.json` — the registry is the source of truth (per `sensor-fire-notification` plan). |
| 9 | **Score exceeds 100%** (`cell_score_pct > 100`) | exit 0, the cell is *over*-firing (more fires than expected) | The script does not clamp. A cell that fires more than the expected rate is *healthy* (the threshold is a *lower* bound). Over-firing is rare and usually indicates a noisy sensor; the operator investigates per the decay-cadence diagnose step. |

## Decay threshold (the "from metric to fix" intent)

The script does not enforce a threshold. The skill surfaces a
*human-facing interpretation* in its summary:

- A cell with `cell_score_pct < 60%` AND `status != intentional_gap`
  is a **decay candidate** per `docs/harness-decay-cadence.md`
  DECAY-1. The 60% threshold is the *quarterly* floor — a sensor
  exists but stopped firing, fires for inert reasons, or is being
  routed around by a newer surface.
- A cell with `status == intentional_gap` is *not* a decay candidate,
  even at 0%. The known intentional gap (`inf-fb-behaviour`) is
  deliberately empty per Bockeler L465-L478 and ADR 0002 L112.
- The 3-step decay loop is in `decay-cadence.md` DECAY-1:
  **Diagnose** (read the per-fire `top_finding` to learn *why* the
  cell is silent) → **Plan a fix or document a deliberate gap**
  (`decommission` ticket, or record the gap in the build-to-delete
  sweep's "kept the assumption" form) → **Re-measure next quarter**
  (the verdict rolls into the next pass's expected counts; a
  deliberate gap three quarters running is itself removal-eligible).

The skill is **information**, not a *decision*. The operator runs
the surface on the cadence above, the surface emits a report, and
the human decides what (if anything) to delete. No cron, no
scheduled hook event, no model-as-own-gate.

## Example

Below is the exact markdown output of
`python3 scripts/evals/harness-coverage.py --format markdown` against the
current `hooks/sensors.json` + governance journal (captured 2026-06-15
on `develop` at plugin version 0.2.2):

```text
| cell_id | status | cell_score_pct | drift_pct | intentional_gap |
|---|---|---:|---:|---|
| comp-ff-maintainability | stale | 0 | 0 |  |
| comp-ff-arch-fit | stale | 0 | 0 |  |
| comp-ff-behaviour | stale | 0 | 0 |  |
| comp-fb-maintainability | stale | 0 | 0 |  |
| comp-fb-arch-fit | stale | 0 | 0 |  |
| comp-fb-behaviour | stale | 0 | 0 |  |
| inf-ff-maintainability | stale | 0 | 0 |  |
| inf-ff-arch-fit | stale | 0 | 0 |  |
| inf-ff-behaviour | stale | 0 | 0 |  |
| inf-fb-maintainability | populated | 1095 | 1095 |  |
| inf-fb-arch-fit | populated | 1095 | 1095 |  |
| inf-fb-behaviour | intentional_gap | 0 | 0 | Bockeler L465-L478 names behav...
**Global:** populated=2 holes=0 gaps=1 score=1095% drift_30d=1095%
_window_sessions=30_
```

How to read this:

- **2 populated cells** (`inf-fb-maintainability`, `inf-fb-arch-fit`)
  in the inferential-FB direction — these are the
  `inferential-structural-judge` sensor's per-axis coverage. Score
  of 1095% is *over*-firing (verdicts in excess of the expected
  30-session rate); the script does not clamp, so the operator
  reads it as "active and healthy."
- **9 stale cells** in the other 3 directions — these are
  sensors that exist (in `hooks/sensors.json`) but did not fire
  in the 30-session window. Per the 60% threshold, all 9 are
  decay candidates; the operator runs the decay-cadence
  diagnose step.
- **1 intentional gap** (`inf-fb-behaviour`) — Bockeler
  L465-L478 names behaviour-inferential-FB as the article's
  open problem; kbg's posture is `verification-gate` +
  `fabrication-verdict-log` + `inferential-structural-judge`,
  all advisory-only per ADR 0002 L112. This is *not* a coverage
  hole; it is a deliberate choice, recorded in
  `KNOWN_INTENTIONAL_GAPS` in the script.

## What this skill does NOT do

- Does **not** write to `~/.claude/governance-events.jsonl`
  (read-only; the autonomy invariant is preserved).
- Does **not** modify `hooks/sensors.json` (the registry is
  hand-curated per the `sensor-fire-notification` plan).
- Does **not** emit any blocking or gating decision (no
  pre-tool-use gate, no ask-gate, no SessionStart/PostToolUse
  consumer; mirrors the inferential-FB "advisory only" invariant
  per `docs/research/inferential-structural-judge-design.md`
  §4(c) and ADR 0002 §L112).
- Does **not** restrict the operator's tool access. Per
  decay-cadence convention the surface gets full tool access so
  the operator can read whatever it needs.
- Does **not** shell out to `claude` via `subprocess` (the script
  reads the journal + registry directly; no LLM in the loop, no
  `pip install`, stdlib only).
- Does **not** auto-fire from any hook (this skill is
  human-triggered; it is the `kbg:harness-coverage` slash command
  surface, not a SessionStart/PostToolUse consumer).
- Does **not** run on a scheduled timer or unattended loop. The
  decay-cadence is a *human* quarterly cadence; the metric is
  the *lens*, not the *gate*. The autonomy invariant
  (`CLAUDE.md` § "The autonomy invariant" + ADR 0002) forbids
  unattended self-repair.
- Does **not** add a regression fixture in this wave (FIX-1 is
  wave 4: `eval/regressions/harness-coverage.json`).

## Cross-references

- **Upstream script:** `scripts/evals/harness-coverage.py` (AGG-1, wave 2).
  The CLI flags + exit-code contract are the only stable
  interface; this skill is a thin wrapper.
- **Upstream design doc:** `docs/research/harness-coverage-metric-design.md`
  (DOC-1, wave 1). Defines the 2x2x3 grid schema, the
  `intentional_gap` annotation, the weights, and the
  "From metric to fix" 3-step operator loop.
- **Decay-cadence DECAY-1:** `docs/harness-decay-cadence.md` §
  "Harness-coverage review" — names this skill as the
  quarterly-lens surface, specifies the 60% threshold, and
  specifies the diagnose / plan / re-measure loop.
- **Autonomy invariant:** `CLAUDE.md` § "The autonomy invariant"
  + `ADR 0002`. This skill is read-only advisory; the operator
  decides what to decommission.
- **Sensor registry:** `hooks/sensors.json` — the registry the
  script reads. Hand-curated per the `sensor-fire-notification`
  plan.
- **Journal schema:** `hooks/JOURNAL-SCHEMA.md` "Envelope
  (nested)" — the JSONL contract the script reads.
- **Peer skill:** `skills/harness-health/SKILL.md` — the
  journal-history view (verdict stream, sensor staleness,
  L553 dual-fire-count). This skill is the *fleet-level* coverage
  view; `harness-health` is the *per-sensor / per-event* view.
- **Future deliverable:** `eval/regressions/harness-coverage.json`
  (FIX-1, wave 4) — 30-session synthetic journal + expected
  grid. The skill's `evals/evals.json` (this file) is the
  *hand-curated* eval coverage; the regression fixture is the
  *deterministic* coverage.
