---
name: harness-health
description: "Read-only query surface over the governance journal. Surfaces structural-judge verdicts (accept/flag/escalate) and per-sensor fire counts / silent-sensor staleness from `hooks/sensors.json`. Use when the user asks 'what's the harness health', 'last 10 verdicts', 'verdicts > 7 in 30 days', or 'silent-sensor count'. Don't use for: the 12-cell decay grid / which cells are empty (use kbg:harness-coverage), deep PR review (kbg:review-pr), security posture (kbg:security-auditor), fleet audit (kbg:harness-audit), or running the scoring engine."
---

# Skill: harness-health

Read-only query layer over `~/.claude/governance-events.jsonl` (the
governance evidence journal per `hooks/JOURNAL-SCHEMA.md`) and
`hooks/sensors.json` (the sensor registry). Surfaces the
`inferential-structural_verdict` event stream emitted by the
SessionEnd hook (`hooks/session/inferential-structural-judge-on-session-end.sh`),
plus per-sensor staleness / fire-count derived by joining the journal
to the registry.

The skill is **advisory only**: it never writes to the journal, never
emits a `permissionDecision`, never invokes the underlying agent. It is
the **SURF-1 deliverable** of the `inferential-structural-test` plan
(`.claude/tasks/inferential-structural-test.md`), implementing the
surfacing contract from
`docs/research/inferential-structural-judge-design.md` §7 (SURF-1
bullet) and §3 (verdict schema).

## When to use

- The user asks "last 10 verdicts", "verdicts > 7 in the last 30 days",
  "silent sensors", or any journal-history view.
- The user wants to know whether a specific sensor is firing
  (`--sensor <name>`), or how many events a sensor has produced
  (`--dual-fire-count`).
- The user wants a single CLI command for the harness-health view
  (no LLM in the loop — `python3 skills/harness-health/scripts/harness-health.py ...`).
- The user wants JSON output for downstream tooling (`--json`).

## When NOT to use

- **Deep PR review** → use `kbg:review-pr` (multi-pass, manual trigger,
  full context).
- **Fleet-level audit** (schema/manifest drift, plugin-cache
  freshness, tool-grant scoping) → use `harness-audit`
  (`bash skills/harness-audit/scripts/audit.sh .`).
- **Security posture** → defer to `security-auditor` agent.
- **The underlying scoring engine** itself → this skill *surfaces*
  verdicts, it does not *produce* them. To re-run or re-score, invoke
  the `inferential-structural-judge` agent directly.
- **State-of-the-harness posture summary** (when that command lands,
  it should defer the journal-history view to this skill and add its
  own posture interpretation on top).

## Quick start

```bash
# last 5 events from the journal
python3 skills/harness-health/scripts/harness-health.py --last 5

# verdicts with score >= 7 in the last 30 days
python3 skills/harness-health/scripts/harness-health.py --min-score 7 --since 30 --event-type verdict

# staleness: per-sensor last_fired + days_silent + fire_count
python3 skills/harness-health/scripts/harness-health.py --staleness

# L553 mitigation: verdict count + fired-event count per sensor
python3 skills/harness-health/scripts/harness-health.py --dual-fire-count

# JSON for downstream tooling
python3 skills/harness-health/scripts/harness-health.py --json --last 10

# no args → help
python3 skills/harness-health/scripts/harness-health.py
```

## Input Contract

### CLI args (all optional; run with no args to print help + exit 0)

| Flag | Type | Default | Meaning |
|---|---|---|---|
| `--last N` | int | none | last N events (applied AFTER other filters) |
| `--since DAYS` | float | none | events newer than N days (fractional OK) |
| `--min-score N` | float | none | filter to events with `fields.score >= N` |
| `--sensor NAME` | str | none | filter by `hook` field (the sensor name) |
| `--event-type` | `verdict`/`skipped`/`all` | `all` | filter by `event` field |
| `--staleness` | bool | false | show per-sensor staleness (last_fired, days_silent, fire_count) from the registry |
| `--dual-fire-count` | bool | false | L553 mitigation: show verdict_count + fired_event_count + last_verdict_score per sensor |
| `--journal PATH` | path | `~/.claude/governance-events.jsonl` | override journal path |
| `--sensors PATH` | path | `hooks/sensors.json` | override sensor registry path |
| `--json` | bool | false | emit machine-readable JSON instead of markdown tables |

### Read paths

- **Journal** — `~/.claude/governance-events.jsonl` by default
  (overridable via `--journal` and the `CLAUDE_JOURNAL_PATH` env var
  per `hooks/JOURNAL-SCHEMA.md` "Test override"). The script reads the
  nested envelope shape (per `JOURNAL-SCHEMA.md` "Envelope (nested)"):
  `{"id", "ts", "session", "hook", "event", "source", "fields": {...}}`.
  The script only filters on `hook`, `event`, `ts`, and `fields.score`;
  every other top-level key is ignored.

- **Sensor registry** — `hooks/sensors.json` by default (overridable
  via `--sensors`). Reads the `sensors[]` array entries: `name`,
  `max_silent_days`, `enabled`, and the other fields are not used by
  this skill.

- **No write paths.** The script NEVER appends to the journal, NEVER
  writes to `hooks/sensors.json`, NEVER invokes the underlying agent.

### Failure modes for the CLI

- **No args** → prints help, exit 0 (task spec; argparse defaults to
  exit 2 on no-args, so the script routes "no CLI flags" to help
  explicitly).
- **Malformed CLI args** → argparse prints usage, exit 2.
- **`--journal PATH` does not exist + verdict view requested** →
  ERROR to stderr, exit 1 (verdicts cannot be served).
- **`--journal PATH` does not exist + staleness/dual-fire requested** →
  WARN to stderr, continue with all sensors shown as silent
  (`last_fired = (never)`, `fire_count = 0`).
- **`--sensors PATH` does not exist + staleness/dual-fire requested** →
  WARN to stderr, skip staleness output, exit 0.
- **Malformed JSONL line** (e.g. truncated write) → WARN to stderr with
  the line number, skip the line, continue (the script never crashes
  on a corrupt journal line — `JOURNAL-SCHEMA.md` "Fail-loud" says the
  *producer* should fail loud, but the *consumer* is best-effort).
- **0 events match** → prints "0 events match" + the query that
  produced zero, exit 0.

## Output Format

Three output shapes, all emitted as markdown tables by default
(`--json` switches to a JSON envelope). Sample output for each shape is
shown below.

### Verdicts list (default; `--last`, `--since`, `--min-score`, `--sensor`)

```text
## Verdicts (n=5)
journal: ~/.claude/governance-events.jsonl

| ts | score | recommendation | hook | top_finding |
|---|---|---|---|---|
| 2026-06-15T14:04:46.417Z | 7 | escalate | inferential-structural-judge | ... |
| 2026-06-15T14:03:38.326Z | 0 | accept | inferential-structural-judge | no edits this session |
| ... |
```

Columns: `ts` (ISO8601 with ms), `score` (int 1-10; 0 is the
empty-diff short-circuit per design doc §6 row 3), `recommendation`
(`accept`/`flag`/`escalate`), `hook` (the sensor name, e.g.
`inferential-structural-judge`), `top_finding` (truncated to 80 chars
with `|` escaped for markdown).

### Sensor staleness (`--staleness`)

```text
## Sensor staleness
sensors: hooks/sensors.json  journal: ~/.claude/governance-events.jsonl

| sensor | max_silent_days | last_fired | days_silent | fire_count | enabled |
|---|---|---|---|---|---|
| auto-mode-denial-log | 90 | (never) | (never) | 0 | True |
| config-change-log | 90 | 2026-06-15T09:45:00.926Z | 0 | 375 | True |
| inferential-structural-judge | 30 | 2026-06-15T14:03:38.326Z | 0 | 2 | True |
| ... |
```

Columns: `sensor` (name), `max_silent_days` (from registry),
`last_fired` (ISO8601 or `(never)`), `days_silent` (int or `(never)`),
`fire_count` (total journal events for this hook), `enabled` (from
registry).

### Dual fire-count (`--dual-fire-count` — the L553 mitigation)

```text
## Dual fire-count (L553 mitigation)
sensors: hooks/sensors.json  journal: ~/.claude/governance-events.jsonl

| sensor | verdict_count | fired_event_count | last_verdict_score |
|---|---|---|---|
| verification-gate | 0 | 64 | (none) |
| inferential-structural-judge | 2 | 2 | 0 |
| ... |
```

Columns: `sensor` (name), `verdict_count` (events with
`event ∈ {inferential_structural_verdict, inferential_structural_verdict_skipped}`),
`fired_event_count` (ALL events for the hook, regardless of event
type), `last_verdict_score` (most recent `fields.score` for the hook,
or `(none)` if no verdict has fired).

**Why this view exists (L553):** a sensor with `verdict_count=0` and
`fired_event_count=0` is silently absent — high quality or inadequate
detection? A sensor with `verdict_count=0` and `fired_event_count>0` is
firing for other reasons (e.g. `verification-gate` fires
`verification_summary`, not `inferential_structural_verdict`). The
side-by-side counts make the difference visible.

### JSON envelope (`--json`)

```jsonc
{
  "journal": "~/.claude/governance-events.jsonl",
  "sensors": "hooks/sensors.json",
  "verdicts": [ /* filtered events with event ∈ JUDGMENT */ ],
  "sensors_registry": [ /* raw sensors.json entries */ ]
}
```

## Failure Modes

Per the design doc §6 (the upstream contract) and the task spec:

| # | Failure | Behavior | Why |
|---|---|---|---|
| 1 | **Journal file missing** + verdict view requested | ERROR to stderr, exit 1 | Verdict queries cannot be served without a journal. A silent empty result would hide a misconfigured `CLAUDE_JOURNAL_PATH`. |
| 2 | **Journal file missing** + only staleness/dual-fire requested | WARN to stderr, continue | Staleness can still render: every sensor shows `last_fired = (never)`, `fire_count = 0`. This is the "all sensors silent" view, which is itself useful. |
| 3 | **`hooks/sensors.json` missing** + staleness/dual-fire requested | WARN to stderr, skip staleness output, exit 0 | Without the registry we cannot enumerate the sensors; we silently degrade to verdict-only. |
| 4 | **Malformed JSONL line** (truncated write, encoding glitch) | WARN to stderr with the line number, skip the line, continue | Per `JOURNAL-SCHEMA.md` "Fail-loud" + "the consumer logs+warns every corrupt line with its line number instead of crashing the whole digest." The script honors that contract. |
| 5 | **0 events match the filter** | Print `0 events match` + the query that produced zero, exit 0 | "No results" is a real result, not an error. The query is echoed so the operator can re-run with corrected flags. |
| 6 | **No CLI args** | Print argparse help, exit 0 | Task spec: a "what does this do" invocation must be self-explanatory, not a stack trace or argparse's default exit 2. |
| 7 | **Empty `hooks/sensors.json`** (zero entries) | `--staleness` / `--dual-fire-count` print the header + an empty table, exit 0 | A freshly-installed harness with no enabled sensors is a valid state. |

## What this skill does NOT do

- Does **not** write to `~/.claude/governance-events.jsonl` (read-only;
  the autonomy invariant is preserved — the journaler is the agent
  hook, not this surface).
- Does **not** invoke the `inferential-structural-judge` agent
  (surfacing is read-only; the agent runs once per session via the
  SessionEnd hook, not on demand from this script).
- Does **not** emit a `permissionDecision` anywhere (no blocking, no
  gating, no ask-gate; mirrors the inferential-FB "advisory only"
  invariant per `docs/research/inferential-structural-judge-design.md`
  §4(c) and ADR 0002 §L115).
- Does **not** add a `disallowedTools:` to any agent's frontmatter (per
  decay-cadence convention).
- Does **not** shell out to `claude` via `subprocess` (the script
  reads the journal directly; no LLM in the loop, no `pip install`,
  stdlib only).
- Does **not** modify `hooks/sensors.json` (the registry is
  hand-curated per the Q6 cross-plan contract; this skill reads it
  but does not edit it).
- Does **not** change `verification-gate.sh` or any other existing
  sensor (the plan's explicit "does not change `verification-gate.sh`"
  guard).

## METHODOLOGY alignment

- **Rule 2 (Simplicity first):** the script is ≤ 200 lines, stdlib
  only, no abstract layers for hypothetical future use. The
  `--dual-fire-count` flag is the L553 mitigation surfaced as a single
  CLI flag, not a multi-step pipeline.
- **Rule 6 (Token budgets are not advisory):** the script does not
  invoke an LLM. The journal + registry are the only inputs; cost is
  bounded by journal size (~1KB/event × ~1k events ≈ 1MB worst case)
  and is a one-shot read, not a per-session agent call.
- **Rule 8 (Read before write):** the dual-fire-count view is a
  read-join of two existing artifacts (journal + registry) — neither
  is mutated.
- **Rule 9 (Tests verify intent):** the script's behavior is verified
  by the 6 done-when checks in the task brief: empty help, `--last 5`
  on an empty journal, `--staleness` on a fresh registry, no audit
  findings, and 200-line cap. These are the 6 greppable assertions that
  would fail if the script regressed.
- **Rule 11 (Match codebase conventions):** the markdown table output
  matches the table shape used in `skills/harness-audit/SKILL.md` and
  the audit-report format; the `[harness-health] WARN:` stderr prefix
  matches the `[<hook-id>] WARN:` convention from the hook scripts.

## See also

- **Upstream contract:**
  `docs/research/inferential-structural-judge-design.md` §3 (verdict
  schema), §6 (failure modes), §7 (SURF-1 bullet — the surfacing
  contract this skill implements).
- **Source of events:** `hooks/session/inferential-structural-judge-on-session-end.sh`
  (HOOK-1) — emits `inferential_structural_verdict` and
  `inferential_structural_verdict_skipped` events.
- **Producer agent:** `agents/inferential-structural-judge.md`
  (AGENT-1) — scores the diff; this skill surfaces the scores.
- **Journal schema:** `hooks/JOURNAL-SCHEMA.md` "Envelope (nested)" —
  the JSONL contract the script reads.
- **Sensor registry:** `hooks/sensors.json` — the registry the
  staleness query reads.
- **Sibling skill:** `skills/harness-audit/SKILL.md` — fleet-level
  audit (manifests, schema, descriptions); this skill is the
  journal-level audit counterpart.
