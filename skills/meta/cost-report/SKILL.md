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

`{ timestamp, session_id, transcript_path, model, model_scoped, stream, agent_type, role, turns, input_tokens, output_tokens, cache_write_tokens, cache_read_tokens, cache_read_per_turn, returns, verify_tokens, verify_cache_read, verify_per_return, rate_verified, estimated_cost_usd }`

`role` (2026-09-03+) is the F9 brief's `[role: …]` tag read from the subagent's first
message — `builder|validator|fixer|re-validator|research|other`, `unknown` when the brief
carried no tag, `null` on orchestrator rows.

`returns` / `verify_tokens` / `verify_cache_read` / `verify_per_return` (2026-09-04+) price
the third handoff cost: main's own tokens from a subagent's return (`<task-notification>`)
to the next Agent dispatch or the next human prompt. `verify_tokens` = input + cache_write +
output summed over those windows (`null` when the row has no return); `verify_cache_read` is
the rent re-read in them; `verify_per_return` lists each window. On the orchestrator row they
cover every notification window in the session; Σ subagent rows can be smaller (task-ids
with no subagent file, non-Claude subagent rows dropped).

**Aggregation rule (the part that must not regress):** for each session with any
`model_scoped` row, take the latest row per (`session_id`, `stream`, `model`,
`agent_type`, `role`) key and sum across keys — a streamless legacy row counts as
`stream: "orchestrator"`, not a fourth bucket. A session with no `model_scoped` rows falls
back to the single latest row by `session_id`. Every element of that key exists because
dropping it double-counted or silently dropped real spend — the incident history, the legacy
row format, the claude-only filter, the `cache_read_per_turn` rent-meter rationale, and the
local-timezone bucketing caveat live in `references/schema-history.md`; read it before
changing the key, the schema, or the tracker.

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
5. By role: subagent spend ranked by the F9 `role` tag (`(untagged)` for pre-2026-09-03
   rows, `unknown` for briefs that carried no tag). Same omission rule as By agent type.
6. Handoff cost: returns per orchestrator turn, then verify tokens per return (median, p90,
   count) for all roles and per role. Rows without `verify_per_return` (pre-2026-09-04) are
   skipped; the section is omitted when none carry it.
7. Orchestrate sessions: count and spend of sessions whose `session_id` appears with
   `mh:orchestrate` in `skill-usage.jsonl` (omitted when that file is absent).
8. Last seven days: date and cost.

Rely on the precomputed `estimated_cost_usd` values written by the tracker; do
not re-estimate pricing from raw tokens here.
