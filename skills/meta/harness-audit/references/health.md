# Mode: `mh:harness-audit --health`

Read-only query layer over `~/.local/share/kbg/metrics/costs.jsonl` — the live cost ledger the `cost-tracker` Stop hook appends one row per session (see `hooks/stop/cost-tracker.sh`).

The verdict + staleness lenses that previously read `~/.claude/governance-events.jsonl` and `hooks/sensors.json` were retired in the v0.6.0 cut reconciliation — both sources are gone (no hook writes the journal; the sensor registry was deleted). `--health` now surfaces the one live signal: per-session token usage and estimated cost. Deep cost reporting lives in `mh:cost-report`.

This mode is **advisory only**: it never writes, never emits a `permissionDecision`, never invokes an LLM. Stdlib only, no subprocess.

Also renders a **skill usage panel** (#90/T11) from `~/.local/share/kbg/metrics/skill-usage.jsonl` — the `session:skill-usage-telemetry` PostToolUse(Skill) hook appends one row per skill invocation. Per-skill invocation counts over the last 7 and 30 days, split by plugin (`mh:` vs `mattpocock-skills:` etc., derived from the skill name's namespace prefix). This is the data source for a future partial-overlap cull — usage evidence instead of feel.

And a **dead-surface panel** (#136) — every skill/agent in THIS repo's own fleet (the `mh` plugin, name read from `.claude-plugin/plugin.json`) with 0 invocations in the last 30 days, split by type, sourced from the same two ledgers (no new data source). A skill carrying `disable-model-invocation: true` is still listed but labeled `manual-only` — a typed `/mh:<name>` still logs a row, so low count is expected there, not suspicious. Hooks have no per-invocation ledger anywhere in this repo, so that row states the source is missing rather than fabricating a zero count. Advisory only — feeds a future deletion sweep, never auto-deletes.

**Scope note:** counts only, no outcome/success field. No reliable success signal exists for a Skill invocation — it loads instructions into context rather than returning an inspectable result the way a Bash exit code does, and Claude Code's own docs don't define one for PostToolUse either. A fabricated constant "outcome" would be a false metric, not a health signal (operator decision, 2026-08-25) — so the panel reports usage, not success rate.

## When to use

- The user asks "token usage / cost this session", "harness health", or "ใช้ token เท่าไหร่".
- The user wants a single CLI cost view (no LLM in the loop).
- The user wants JSON output for downstream tooling (`--json`).

## When NOT to use

- **Deep cost report / historical trends** → use `mh:cost-report`.
- **Fleet-level audit** (schema/manifest drift, plugin-cache freshness, tool-grant scoping) → use `harness-audit` default (`bash "${CLAUDE_SKILL_DIR}/scripts/audit.sh"`).
- **Deep PR review** → use `mattpocock-skills:code-review`.
- **Security posture** → defer to `mh:security-auditor`.

## Quick start

```bash
# last 5 sessions
python3 "${CLAUDE_SKILL_DIR}/scripts/harness-health.py" --last 5

# sessions in the last 30 days
python3 "${CLAUDE_SKILL_DIR}/scripts/harness-health.py" --since 30

# JSON for downstream tooling
python3 "${CLAUDE_SKILL_DIR}/scripts/harness-health.py" --json --last 10

# no args → help
python3 "${CLAUDE_SKILL_DIR}/scripts/harness-health.py"
```

## CLI args (all optional; no args → help + exit 0)

| Flag | Type | Default | Meaning |
|---|---|---|---|
| `--last N` | int | none | last N sessions (applied AFTER other filters) |
| `--since DAYS` | float | none | sessions newer than N days |
| `--costs PATH` | path | `~/.local/share/kbg/metrics/costs.jsonl` | override cost ledger path |
| `--skills PATH` | path | `~/.local/share/kbg/metrics/skill-usage.jsonl` | override skill-usage ledger path |
| `--root PATH` | path | this file's own repo root (4 parents up) | fleet root for the dead-surface panel — `skills/`, `agents/`, `hooks/`, `.claude-plugin/` |
| `--json` | bool | false | emit JSON instead of markdown |

## Read paths

- **Cost ledger** — `~/.local/share/kbg/metrics/costs.jsonl` by default. Each row: `timestamp`, `session_id`, `transcript_path`, `model`, `input_tokens`, `output_tokens`, `cache_write_tokens`, `cache_read_tokens`, `estimated_cost_usd`.
- **Skill-usage ledger** — `~/.local/share/kbg/metrics/skill-usage.jsonl` by default (`--skills PATH` overrides). Each row: `ts`, `session_id`, `skill` (full namespaced name, e.g. `mh:harness-audit`), `plugin` (the namespace prefix before `:`, or `unknown`).
- **Fleet root** — `--root PATH` (default: this file's own repo root). Read-only `os.walk`/`glob` over `skills/`, `agents/`, `hooks/`, and `.claude-plugin/plugin.json` — same filters as `checks/01-fleet-count.sh`. No new data source: the dead-surface panel reuses the cost and skill-usage ledgers above.
- **No write paths.** The script never appends to either ledger, never invokes an agent, never emits a `permissionDecision`.

## Output Format

```text
## Token usage (costs.jsonl)
ledger: ~/.local/share/kbg/metrics/costs.jsonl

| ts | session | model | input | output | cache_write | cache_read | est_cost_usd |
|---|---|---|---|---|---|---|---|
| 2026-06-30T14:23:00Z | a1b2c3d4 | claude-... | 12,345 | 1,200 | 8,000 | 45,000 | 0.1234 |

**Σ across N session(s): input ... · output ... · cache_write ... · cache_read ... · est_cost $X.XXXX**

## Skill usage (skill-usage.jsonl)
ledger: ~/.local/share/kbg/metrics/skill-usage.jsonl

| plugin | skill | last 7d | last 30d |
|---|---|---|---|
| mh | mh:harness-audit | 3 | 11 |
| mattpocock-skills | mattpocock-skills:code-review | 1 | 4 |

**Σ last 7d: 4 invocation(s) · last 30d: 15 invocation(s)** (mh=11, mattpocock-skills=4)

## Dead surfaces (0 invocations in last 30d)
fleet root: /path/to/matt-harness

| type | name | note |
|---|---|---|
| skill | mh:some-unused-skill | |
| skill | mh:ship-merge | manual-only (disable-model-invocation) |
| agent | mh:some-unused-agent | |

hooks: 41 hook(s) in fleet — no invocation ledger exists, source missing (see issue #136)

**N dead skill(s) · M dead agent(s)** — INFO only: usage evidence for a future deletion sweep, never auto-deletes.
```

`estimated_cost_usd` uses the heuristic rates in `hooks/stop/cost-tracker.sh` (haiku/opus/sonnet tiers) — it is an estimate, not a bill.

## Failure modes for the CLI

- **No args** → prints help, exit 0.
- **Cost ledger missing** → ERROR to stderr, exit 1 (cost cannot be served without the ledger).
- **Skill-usage ledger missing** → renders "0 rows" for that panel, exit 0 — a fresh install with no skill invocations yet is expected, not an error.
- **Malformed JSONL line** (either ledger) → WARN to stderr with the line number, skip the line, continue.
- **0 rows match** → prints "0 rows" + a note, exit 0.
- **Every fleet surface invoked in the last 30d** → the dead-surface panel still prints, with "0 dead skill(s), 0 dead agent(s)" rather than omitting the section.
- **No per-hook invocation ledger** → the hooks line always states the source is missing; it never reports a fabricated zero count.

## What this skill does NOT do

- Does **not** write to either ledger (read-only; the cost-tracker Stop hook and skill-usage-telemetry PostToolUse hook are the sole writers).
- Does **not** invoke an LLM or `claude` via subprocess (stdlib only).
- Does **not** emit a `permissionDecision` anywhere (no blocking, no gating; advisory only).
- Does **not** report skill success/failure rates — see the scope note above.

## See also

- **Cost writer:** `hooks/stop/cost-tracker.sh` (appends one row per session; the rate table).
- **Skill-usage writer:** `hooks/session/skill-usage-telemetry.sh` (appends one row per skill invocation; PostToolUse matched on `Skill`).
- **Deep cost report:** `mh:cost-report` (historical trends, not just last-N).
- **Sibling skill:** `skills/meta/harness-audit/SKILL.md` — fleet-level audit; this is the cost counterpart.