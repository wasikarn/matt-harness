# Mode: `kbg:harness-audit --health`

Read-only query layer over `~/.local/share/kbg/metrics/costs.jsonl` — the live cost ledger the `cost-tracker` Stop hook appends one row per session (see `hooks/stop/cost-tracker.sh`).

The verdict + staleness lenses that previously read `~/.claude/governance-events.jsonl` and `hooks/sensors.json` were retired in the v0.6.0 cut reconciliation — both sources are gone (no hook writes the journal; the sensor registry was deleted). `--health` now surfaces the one live signal: per-session token usage and estimated cost. Deep cost reporting lives in `kbg:cost-report`.

This mode is **advisory only**: it never writes, never emits a `permissionDecision`, never invokes an LLM. Stdlib only, no subprocess.

## When to use

- The user asks "token usage / cost this session", "harness health", or "ใช้ token เท่าไหร่".
- The user wants a single CLI cost view (no LLM in the loop).
- The user wants JSON output for downstream tooling (`--json`).

## When NOT to use

- **Deep cost report / historical trends** → use `kbg:cost-report`.
- **Fleet-level audit** (schema/manifest drift, plugin-cache freshness, tool-grant scoping) → use `harness-audit` default (`bash "${CLAUDE_SKILL_DIR}/scripts/audit.sh"`).
- **Deep PR review** → use `kbg:review-pr`.
- **Security posture** → defer to `kbg:security-auditor`.

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
| `--costs PATH` | path | `~/.local/share/kbg/metrics/costs.jsonl` | override ledger path |
| `--json` | bool | false | emit JSON instead of markdown |

## Read paths

- **Ledger** — `~/.local/share/kbg/metrics/costs.jsonl` by default. Each row: `timestamp`, `session_id`, `transcript_path`, `model`, `input_tokens`, `output_tokens`, `cache_write_tokens`, `cache_read_tokens`, `estimated_cost_usd`.
- **No write paths.** The script never appends to the ledger, never invokes an agent, never emits a `permissionDecision`.

## Output Format

```text
## Token usage (costs.jsonl)
ledger: ~/.local/share/kbg/metrics/costs.jsonl

| ts | session | model | input | output | cache_write | cache_read | est_cost_usd |
|---|---|---|---|---|---|---|---|
| 2026-06-30T14:23:00Z | a1b2c3d4 | claude-... | 12,345 | 1,200 | 8,000 | 45,000 | 0.1234 |

**Σ across N session(s): input ... · output ... · cache_write ... · cache_read ... · est_cost $X.XXXX**
```

`estimated_cost_usd` uses the heuristic rates in `hooks/stop/cost-tracker.sh` (haiku/opus/sonnet tiers) — it is an estimate, not a bill.

## Failure modes for the CLI

- **No args** → prints help, exit 0.
- **Ledger missing** → ERROR to stderr, exit 1 (cost cannot be served without the ledger).
- **Malformed JSONL line** → WARN to stderr with the line number, skip the line, continue.
- **0 rows match** → prints "0 rows" + a note, exit 0.

## What this skill does NOT do

- Does **not** write to the ledger (read-only; the cost-tracker Stop hook is the sole writer).
- Does **not** invoke an LLM or `claude` via subprocess (stdlib only).
- Does **not** emit a `permissionDecision` anywhere (no blocking, no gating; advisory only).

## See also

- **Writer:** `hooks/stop/cost-tracker.sh` (appends one row per session; the rate table).
- **Deep cost report:** `kbg:cost-report` (historical trends, not just last-N).
- **Sibling skill:** `skills/harness-audit/SKILL.md` — fleet-level audit; this is the cost counterpart.