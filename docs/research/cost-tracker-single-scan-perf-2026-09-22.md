# cost-tracker.sh single-scan performance fix

Date: 2026-09-22. TDD refactor loop (`mattpocock-skills:tdd`), triggered by a whole-repo
Big-O sweep. Full detail lives in the commit diff and `tests/hooks/test-session-stop.sh`;
this doc keeps the measurement trail the code comments cite.

## Root cause

`hooks/stop/cost-tracker.sh` fires on every `Stop` event (every turn). Before this fix it
re-scanned the main session transcript with 3-5 separate full-file `jq -nR 'inputs | ...'`
invocations per call:

- `build_verify_map "$transcript"` (orchestrator typemap)
- `emit_rows orchestrator ...` (usage extraction)
- `emit_codex_invocations "$transcript" ...`
- when subagents exist: `build_type_map` recomputed its own `parent_map` from `$transcript`
  **and** called `build_verify_map "$transcript"` a second time — the identical value,
  recomputed from scratch.

Each pass parses the whole file from disk. Over a session of T turns (transcript growing
each turn), cumulative work is O(T) per Stop call, i.e. O(T²) total bytes parsed across
the session.

## Measurement

Largest real transcript on disk at measurement time:
`~/.claude/projects/-Users-kobig-Codes-Assignments-portfolio-report-service/*.jsonl`,
158,369,996 bytes / 42,838 lines.

| | jq passes over main transcript | wall time / Stop call |
|---|---|---|
| Before | 5 (measured via PATH-shimmed jq, see the pass-count test) | 9.5s |
| After | 1 | 5.2s |

The declining-but-not-5x-proportional speedup is expected: `[inputs \| try fromjson]`
still parses+materializes the whole file once, and JSON re-encoding/shell overhead don't
scale with pass count. The eliminated cost is specifically the 4 *redundant* disk-read +
parse passes.

## Design

Added `scan_transcript()`: one jq invocation that parses the file into `$lines` once,
then computes `verify_map`, `parent_map`, `usages`, and `codex` as four independent
sub-expressions over the same in-memory array. All four are individually wrapped in
`try/catch` (matching each original function's own fallback: `{}` for verify_map,
parent_map, and codex; `{__error:true}` for usages, detected by the caller to emit the
jq_failed sentinel). This was not the first draft: an earlier version left verify_map/
parent_map/codex unwrapped on the theory that only `usages` ever indexes
`.message.usage.<field>` arithmetically — true for parent_map/codex, but **wrong for
verify_map**, which does `.message.usage.input_tokens // 0` inside its own reduce once a
verify-window is open. A malformed usage line arriving *inside* an open window (after a
real agent dispatch's `<task-notification>`, before the closing Agent tool_use — not
covered by the original H7 fixture, which has no dispatch at all) threw inside the whole
combined jq object construction, aborting all four keys at once with no sentinel, no
error, nothing written — silently losing the exact guarantee H7 exists to provide. Caught
by writing a fixture for that specific shape (dispatch → notification → malformed-usage
line) and confirming it failed red before the fix; now covered permanently in
`tests/hooks/test-session-stop.sh`.

`emit_rows` was split into `raw_records` (file I/O + jq_failed sentinel, unchanged) and
`group_and_price` (pure grouping/pricing over already-extracted JSON) so both the
subagent path (still file-scanning — subagent transcripts are small, not the measured
hotspot) and the orchestrator path (now pre-scanned) share one pricing implementation.

`build_type_map` now takes `parent_map`/`vmap` as pre-computed arguments instead of
re-deriving them from the parent transcript.

Codex tool_use tallies from the main transcript (via `scan_transcript`) and from subagent
files (via `emit_codex_invocations`, unchanged) are merged **additively per key** — the
original single combined call effectively summed tool_use blocks across every file's
lines together, so two independent tallies must be added, not have one overwrite the
other. Covered by a dedicated test (main transcript + subagent both calling
`codex:review` → count 2, not 1).

## Bug found during the TDD loop

Making `parent_map` computation unconditional (it used to run only when subagents
existed) surfaced a latent crash: an `Agent` tool_use block with no `.id` made
`{(.id): ...}` throw `Cannot use null (null) as object key` in jq. This bug existed in
the original code too (`build_type_map`'s inline parent_map computation had the same
shape) but was never exercised because it was gated behind "subagents present," and no
test fixture combining "no subagents" with "an id-less Agent tool_use" ever ran through
it. Fixed with `select(.id != null)` — real transcripts always carry a tool_use id, so
this changes nothing for real usage; it only stops a crash on malformed input.

## Verification

- `bash tests/hooks/test-session-stop.sh` — 36/36 (34 pre-existing regression tests
  unchanged + 2 new: the pass-count assertion and the codex-merge assertion).
- `bash skills/meta/harness-audit/scripts/audit.sh` — 0 CRIT.
- `bash scripts/run-gauntlet.sh` — all layers pass.

## Declined in the same session

A second candidate (`skills/meta/memory-lint/scripts/memory-lint.py`'s
`difflib.get_close_matches` dangling-link fuzzy match, O(D×N) where N=378 memory-store
files) was measured and declined: 0.05ms/call at the real N=377, 2.4ms even at a
synthetic N=5,000, because `get_close_matches` already short-circuits via
`real_quick_ratio`/`quick_ratio` internally. Not a hotspot; no code change made.
