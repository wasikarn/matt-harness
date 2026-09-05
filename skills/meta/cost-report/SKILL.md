---
description: "Cost-report: local Claude Code spend from the cost-tracker metrics log. Use when checking session spend. Don't use for scheduling or budget alerts (none exist)."
name: cost-report
argument-hint: "[csv]"
model: inherit
effort: low
---

# Cost Report

Summarize local Claude Code spend by day, model, and session from the metrics
log that `hooks/stop/cost-tracker.sh` writes (ported from ECC originally, but it
lives and runs in this repo).

## Where the data lives

The tracker appends JSON rows to `~/.local/share/kbg/metrics/costs.jsonl` — one per
(model, stream, agent_type) actually used in the session so far, tagged
`model_scoped: true`; each row re-derives cumulative totals from the full transcript
(stateless). Row schema:

`{ timestamp, session_id, transcript_path, model, model_scoped, dedup_usage, usage_pick, stream, agent_type, turns, input_tokens, output_tokens, cache_write_tokens, cache_read_tokens, cache_read_per_turn, rate_verified, estimated_cost_usd }`

`stream` is `orchestrator` (the main transcript) or `subagent` (each `subagents/agent-*.jsonl`);
`agent_type` is the Agent tool's `subagent_type` from the sibling `.meta.json`, `unknown` when
missing, `null` on orchestrator rows. Older rows may carry extra fields from retired schemas;
the report ignores unknown keys.

`dedup_usage: true` (2026-09-04+) marks rows that count each API response once by
`message.id`; rows without it counted one JSONL line per content block and run ~2.4x high on
`turns` and tokens. `usage_pick: "last"` (v0.68.641+) marks rows that keep the last line per
id (the final `output_tokens`); `dedup_usage` rows without it kept the first line and run
~39% low on `output_tokens`. Neither era is rewritten; the report prints a note instead.

**Aggregation rule (the part that must not regress):** for each session with any
`model_scoped` row, take the latest row per (`session_id`, `stream`, `model`,
`agent_type`) key and sum across keys — a streamless legacy row counts as
`stream: "orchestrator"`, not a fourth bucket. A session with no `model_scoped` rows falls
back to the single latest row by `session_id`. Every element of that key exists because
dropping it double-counted real spend (a streamless legacy row plus a same-model
orchestrator row overcounted one session by $8.07, 2026-08-07); the tests in
`tests/skills/test-cost-report.sh` pin each element. Days bucket by local calendar day, not UTC.

Two standing caveats when reading totals: `rate_verified: false` rows are priced at a
Sonnet-rate guess (the `(rate unverified)` tag is the only signal — totals are "correctly
summed", not "correctly priced"), and pre-2026-08-07 rows carry no subagent spend at all, so
never read a pre/post difference as a spending change.

## What this command does

1. Check that `~/.local/share/kbg/metrics/costs.jsonl` exists. If it does not, tell the
   user the tracker is not set up yet (it populates after the first session ends
   with the `stop:cost-tracker` hook enabled).
2. Run the report script (report + CSV logic live in one bundled node file —
   `node` rather than `sqlite3`/`jq` so it works identically on macOS, Linux,
   and Windows; the dedup logic is regression-tested by
   `tests/skills/test-cost-report.sh` against this same file):

```bash
node "${MH_PLUGIN_ROOT}/scripts/workflows/cost-report-dedup.js"
```

3. For CSV export (`/cost-report csv` — last 100 raw rows):

```bash
node "${MH_PLUGIN_ROOT}/scripts/workflows/cost-report-dedup.js" csv
```

## Report format

1. Summary: today, yesterday, total, session count.
2. By model: models ranked by total cost.
3. By stream: orchestrator vs subagent, plus the orchestrator's context-carried-per-turn.
   Omitted entirely when no row carries `stream` (all data predates 2026-08-07).
4. By agent type: subagent spend only, ranked by `agent_type`, including an `(unknown)`
   row for untyped subagent rows; a `tok` column (input+output tokens) sits next to cost
   so ranking still works when `rate_verified` is false. Omitted entirely when no row
   carries `stream: subagent` (all data predates 2026-08-07).
5. Last seven days: date and cost.

Rely on the precomputed `estimated_cost_usd` values written by the tracker; do
not re-estimate pricing from raw tokens here.
