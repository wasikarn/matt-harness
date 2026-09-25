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
  cache_write_tokens_1h, cache_read_tokens, cache_read_per_turn, returns, verify_tokens,
  verify_cache_read, verify_per_return, rate_verified, mh_version, head_commit,
  estimated_cost_usd }
```

- `stream`: `orchestrator` (the main transcript) or `subagent` (each `subagents/agent-*.jsonl`).
- `agent_type`: the Agent tool's `subagent_type` from the sibling `.meta.json`; `unknown` when
  missing; `null` on orchestrator rows.
- `rate_verified: false`: model matched no rate-table entry, priced at the Sonnet rate.
- A separate row shape `{ timestamp, session_id, codex_invocations: {name: count} }` counts
  `codex:*` Skill and Agent calls; it has no model and is summed on its own.
- Older rows carry fields from retired schemas; unknown keys are ignored.
- `cost-report-dedup.js`'s `csv` mode's header and column order must be kept in sync with any
  field added here (deep-audit finding, 2026-09-25: `cache_write_tokens_1h` shipped in the row
  but not in the CSV for one commit, so the CSV silently dropped every 1h-write token while
  `estimated_cost_usd`, computed independently, stayed correct — a gap that looks like nothing
  is wrong until someone reads the CSV specifically).

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
| no `cache_write_tokens_1h` | before the #162 fix (1.1.118, 2026-09-25) | `cache_write_tokens` is every cache-write token, mispriced entirely at the 5-minute rate. Full-corpus measurement on this machine, 2026-09-25 (not a sample): of 183,970 `cache_creation` usage lines, 99.30% of cache-write tokens were 1-hour-TTL, 0.70% 5-minute — so `estimated_cost_usd` on these rows undercounts cache-write cost, not just theoretically |
| `cache_write_tokens_1h` present, `> 0` | after the #162 fix (1.1.118), real 1h writes seen | `cache_write_tokens` is 5-minute-TTL writes only; `cache_write_tokens_1h` is the 1-hour-TTL subset, priced separately and correctly. Historical rows are not backfilled |
| `cache_write_tokens_1h` present, `== 0`, deep-audit correction 2026-09-25 | after the #162 fix, no 1h writes OR a pre-breakdown transcript | Not distinguishable from this field alone. The flat-field fallback (no `cache_creation` breakdown object at all) exists for defensive/older-shape compatibility; on this machine it has never actually fired — every local line with nonzero cache-write tokens (175,524 of them) carries the breakdown object, so the "35/404 legacy transcripts" figure an earlier draft of this row cited was wrong: those files simply had zero cache-write activity, not a pre-breakdown shape |
| `mh_version: "1.1.118"` rows, multi-iteration turns only | pushed to `develop` as commit `dc3e654b`, permanent history | That version's `raw_records()`/`scan_transcript()` read `.message.usage.cache_creation` directly. On a multi-tool-round-trip turn, that top-level object is a copy of `.message.usage.iterations[0]`'s own `cache_creation`, not a sum across `.message.usage.iterations[]` — unlike the flat `cache_creation_input_tokens` field, which does sum across iterations. Confirmed on 2,604 real local lines: top-level flat matched the true (iteration-summed) total 98.7% of the time; the top-level breakdown matched it only 0.9%. A `mh:deep-audit` pass the same day caught this while the installed plugin cache (`~/.claude/plugins/cache/wasikarn/mh/`) was still at 1.1.117 — confirmed by grepping the installed hook for `cw1h` (0 matches) — so no live Stop hook ever ran this version; the repo-vs-plugin-cache distinction is itself a separate claim, see CLAUDE.md's own gotcha on this |
| `mh_version: "1.1.119"`+ rows | after the same-day follow-up fix | Both extraction sites now bind `(.message.usage.iterations // []) as $its` and, when non-empty, anchor `cache_write_tokens_1h` to `min(sum of iteration 1h tokens, top-level flat)` and derive `cache_write_tokens` as the remainder — one mechanism closing three gaps a naive per-iteration sum reopened (`mh:blind-spot-hunter`, same day): an iteration missing its own `cache_creation` object no longer zeroes the whole row (it now falls through to the flat total instead of vanishing under the nonzero filter); a Claude Code background-session transcript that copies one `message.id` across sibling files with every top-level counter zeroed except `iterations` no longer manufactures real dollars on the zeroed copies (anchors to the copy's own zero flat); and an `advisor_message` iteration billing a *different* model can no longer push a row's total above its own top-level flat, bounding — though not perfectly attributing — the misattribution risk |

No legacy era is rewritten. The report prints a `note:` line for each of the three token-count
and cache-write-split eras present; the no-`stream` era shows as a missing section instead.

A row with `error: "jq_failed"` (and no token fields) is the tracker's sentinel for a jq pass
that died; the report never aggregates it, and prints one `warning:` line per session with the
row count and the session id prefix (2026-09-21). `returns per orchestrator turn` divides by
the turns of every orchestrator row carrying `verify_per_return`, including zero-return rows.

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
