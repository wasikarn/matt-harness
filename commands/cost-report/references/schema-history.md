# cost-report — row-schema history and verified incidents

Moved verbatim from the command body (2026-08-23, 200-LOC cap refactor). This is the
design/incident record behind COMMAND.md's aggregation rules — read it before changing the
dedup key, the schema, or the tracker's write format.

## Per-model (`model_scoped`) design

The tracker appends one or more JSON objects per session-stop, one per **model actually used in
that session so far, split further by `agent_type` for subagent spend**. Every stop re-derives
cumulative totals from the full transcript (stateless, no separate counter file), groups
assistant turns by `.message.model` (and, within the subagent stream, by `agent_type`), and
writes each model's own cumulative `input_tokens`/`output_tokens`/`estimated_cost_usd`, priced
at that model's own rate. These rows carry `model_scoped: true`. The hook's per-model token
math was verified 2026-07-28 against a real 3-model transcript (`claude-opus-4-8`,
`claude-sonnet-5`, `glm-5.2`): each model's cost matched a hand computation. That predates the
claude-only filter added 2026-08-07 (below); the third model only shows multi-model grouping
works, not that it's still tracked today. The report's aggregation of `model_scoped` rows is
regression-gated only against a single-row synthetic case — zero such rows exist in production
yet, so treat multi-row aggregation as untested until a real multi-model session produces one.

## Legacy (pre-`model_scoped`) design and its fallback

**Rows written before this fix (no `model_scoped` field) used a different, coarser design**:
one row per stop, summing token usage across the *entire* transcript with no per-model split,
priced at whichever model produced the most recent turn. A session that switched models had
`input_tokens`/`estimated_cost_usd` monotonically increasing regardless of which model was
active (confirmed against production data, 2026-07-28). **For a session with no `model_scoped`
rows at all** (it stopped for the last time before this fix shipped, so it never gets an
updated row), the report falls back to the old behavior: dedup by `session_id` alone, take the
single latest row — the correct aggregation of what the old design recorded (verified by an
independent recomputation landing on the identical figure, $34,698.3252, 2026-07-28), and the
best available total for an unmeasurable session. A session with at least one `model_scoped`
row uses **only** those rows — never mixed with its older rows, since a `model_scoped` row
recomputes from the whole transcript and already supersedes anything the old design recorded
earlier in that same session.

**Prior mistake, corrected the same day:** an earlier draft wrongly deduped old-format rows by
(`session_id`, `model`) and summed them — inflating the true $34,698 total to a fabricated
$53,883, since old rows are whole-session snapshots, so summing several double- and
triple-counts the same tokens. This hook change makes (`session_id`, `model`) dedup correct,
for `model_scoped` rows only.

Neither design gives a correct *dollar* total on its own: `rate_verified: false` rows are
priced at a Sonnet-rate guess — on 2026-07-28's data (still mostly old-format rows) that was
over half the total, $17,510 of $34,698. The report's `(rate unverified)` tag on each affected
model is the only signal; treat any total as "correctly summed," not "correctly priced," until
every model in the rate table has a verified rate.

## `stream` (added 2026-08-07)

`stream` is `"orchestrator"` (the main thread, `.transcript_path`) or `"subagent"` (every file
under the sibling `<session-id>/subagents/` directory). Absent on all rows written before that
— those are orchestrator-only totals, since the hook never read the subagent directory, so
subagent spend was missing from every historical row rather than folded into it. **Do not
compare a pre-2026-08-07 session's total against a later one and read the difference as a
spending change.**

Because both streams can carry the same `model` inside one session, the (`session_id`,
`model`) dedup key became (`session_id`, `stream`, `model`) — without `stream` in the key the
two rows collide and one is silently dropped, the same undercount the split was added to fix.
A streamless legacy row counts as `stream: "orchestrator"` in the dedup key, not a fourth
bucket — a session spanning the upgrade would otherwise double-count (confirmed live: an $8.07
overcount on one real session, 2026-08-07).

## `agent_type` (added 2026-08-07)

`agent_type` is the Agent tool's `subagent_type` value (`"general-purpose"`, `"Explore"`,
`"kbg:code-reviewer"`, …), read from the `agentType` field in each subagent's
`agent-<id>.meta.json` sibling. `null` on every orchestrator row (the main thread has no
subagent type); `"unknown"` on a subagent row whose meta.json was missing or unreadable, so a
lookup gap never silently drops spend. The dedup key widens to (`session_id`, `stream`,
`model`, `agent_type`) for the same reason `stream` joined it: two agent types on the same
model in one session are two different rows, not duplicates — without `agent_type` in the key,
one silently drops the other's spend.

## Claude-only filter (operator request, 2026-08-07)

A session can run non-Claude models — a proxy that swaps `ANTHROPIC_BASE_URL` — with confirmed
production spend this way (`minimax-m3`, `glm-5.2`, `kimi-k2.7-code`, `nemotron-3-super`). The
hook drops any assistant turn whose `.message.model` doesn't match `claude-*` before grouping —
not priced at a guessed rate, not folded into an `"unknown"` row, simply not written. A
transcript with no Claude turns writes no row. Historical non-Claude rows in `costs.jsonl` stay
untouched — this only affects future writes; the report still sums whatever `model_scoped` rows
exist, Claude or not.

## `turns` and `cache_read_per_turn`

`turns` is the assistant-turn count behind the row, and `cache_read_per_turn` is
`cache_read_tokens ÷ turns` **for that row's own model** — the hook groups by model before
counting turns, so a session that switched models has one ratio per model, not one for the
session. The By-stream block re-derives a session-level figure by summing tokens and turns
across every orchestrator row first, then dividing; that deliberately mixes models, since the
question there is how much context the main thread carried, not which model it talked to. On
the orchestrator row, that ratio measures how much context the main thread carries into
*every* turn, re-billed each time — the cost the article "The Orchestrator's Tax" names and the
reason for this split (`docs/research/orchestrator-tax-gap-analysis-2026-08-07.md`). A rising
`cache_read_per_turn` across sessions means the main thread is accumulating more than it
needs; that number, not the dollar total, is the one to watch.

## Timezone bucketing

`timestamp` is stored in UTC (`Z` suffix), but "today"/"yesterday"/the last-7-days buckets are
computed from each `Date`'s **local** calendar fields (`getFullYear`/`getMonth`/`getDate`, not
`toISOString`) — matching UTC calendar days would instead put several hours of a user's actual
"today" spend under "yesterday" for anyone west of UTC (reproduced 2026-07-28 in UTC+7: a
UTC-bucketed report misclassified $972 of the prior day's spend as "today"). This depends on
the Node process's resolved local timezone
(`Intl.DateTimeFormat().resolvedOptions().timeZone`, which follows the machine's system
timezone when `TZ` is unset) — correct for a user running this command on their own machine,
but if invoked in a context whose system/`TZ` timezone doesn't match the reader's own (a
container, a remote/headless session), the buckets follow that environment's zone instead.
