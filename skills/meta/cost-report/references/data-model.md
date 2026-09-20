# cost-report data model

Read when changing `../scripts/cost-report-dedup.js` or `hooks/stop/cost-tracker.sh`.
The report itself needs none of this.

## Rows

The tracker appends one JSON row per (model, stream, agent_type) used in the session so far,
tagged `model_scoped: true`. Each row re-derives cumulative totals from the full transcript,
so the latest row per key is the session's current total, not an increment.

```
{ timestamp, session_id, transcript_path, model, model_scoped, dedup_usage, usage_pick,
  stream, agent_type, turns, input_tokens, output_tokens, cache_write_tokens,
  cache_read_tokens, cache_read_per_turn, returns, verify_tokens, verify_cache_read,
  verify_per_return, rate_verified, mh_version, head_commit, estimated_cost_usd }
```

- `stream`: `orchestrator` (the main transcript) or `subagent` (each `subagents/agent-*.jsonl`).
- `agent_type`: the Agent tool's `subagent_type` from the sibling `.meta.json`; `unknown` when
  missing; `null` on orchestrator rows.
- `rate_verified: false`: model matched no rate-table entry, priced at the Sonnet rate.
- A separate row shape `{ timestamp, session_id, codex_invocations: {name: count} }` counts
  `codex:*` Skill and Agent calls; it has no model and is summed on its own.
- Older rows carry fields from retired schemas; unknown keys are ignored.

## `returns`, `verify_tokens`, `verify_cache_read`, `verify_per_return` (restored 2026-09-20)

Handoff cost: main's own tokens spent reading a subagent's result, re-reading files to verify
it, and deciding — the cost the validation chain never priced. A subagent's return does not
arrive as the Agent tool_result (that only says "Async agent launched"); it lands later as a
`user` line whose string content starts `<task-notification>` and whose `<task-id>` is the
subagent's file id (`agent-<id>.jsonl`). `cost-tracker.sh`'s `build_verify_map` opens a window
at each such line and closes it at the next notification, the first assistant line carrying an
Agent `tool_use` (counted — deciding to dispatch is part of the handoff), or EOF; every
assistant line inside contributes input + cache_write + output to `v` and cache_read to `c`.
`cache_write` counts as fresh input because under prompt caching raw `input_tokens` is ~2 per
turn — leaving it out would report the cost as near zero. Fail-open: any parse error gives an
empty map, so rows keep `returns: 0`, `verify_tokens: null` rather than vanishing. Not in the
dedup key (derived per file, not a population split). On the orchestrator row the fields cover
every return in the session. This was first shipped in `6603c384` (2026-09-04) grouped by the
`role` tag, then both were deleted together in `2cac98c8`; this restore deliberately keeps
`role` out (tracked separately, see the harness gap-audit's M14) and reports one combined
"all subagents" line instead of a per-role breakdown. Rows before this restore carry none of
these fields and the Handoff cost section skips them.

## Eras

| marker | rows | effect |
|---|---|---|
| no `stream` | before 2026-08-07 | orchestrator-only; no subagent spend recorded |
| no `dedup_usage` | before 2026-09-04 | usage summed once per JSONL content-block line: turns, tokens, and cost about 2.4x high |
| `dedup_usage` without `usage_pick: "last"` | v0.68.639 to v0.68.640 | first line per `message.id` kept, a streaming placeholder: `output_tokens` and cost about 39% low |
| `dedup_usage: true, usage_pick: "last"` | v0.68.641+ | one count per API response, final output count |

No legacy era is rewritten. The report prints a `note:` line for each of the two token-count
eras present; the no-`stream` era shows as a missing section instead.

## Aggregation rule

For each session with any `model_scoped` row: take the latest row per
(`session_id`, `stream`, `model`, `agent_type`) and sum across keys. A row with no `stream`
counts as `stream: "orchestrator"`, not a fourth bucket. A session with no `model_scoped` row
falls back to its single latest row. Days bucket by local calendar day.

Every element of that key exists because dropping it double-counted real spend: a streamless
legacy row plus a same-model orchestrator row overcounted one session by $8.07 on 2026-08-07,
and two agent types on one model would collapse into one bucket. `tests/skills/test-cost-report.sh`
pins each element with fixtures whose wrong answers differ from the right one.

## Why node

Report and CSV logic live in one bundled file so macOS, Linux, and Windows run the same code
with no `jq` or `sqlite3` dependency, and the test runs that file directly.
