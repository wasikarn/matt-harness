#!/usr/bin/env bash
# Gate: ask when the MAIN session's own cumulative inline Write/Edit/NotebookEdit
# count for THIS session crosses a budget -- a soft nudge toward delegation,
# never a block. Opt-in and off by default.
#
# Why: skills/workflow/orchestrate/reference.md already documents a 9-clause
# "inline-wins checklist" (prose-only) for when main may legitimately edit files
# directly instead of dispatching. This is a computational backstop for that
# model, not a replacement for it -- it fires on VOLUME, not on clause
# compliance, and can't tell a legitimate clause-1 inline edit from an
# undisciplined one. Naming the applicable clause is still the actual
# mechanism; this just nudges when the volume itself looks off regardless of
# whether each individual edit was justified.
#
# NOT an absolute "main never executes" rule. A 5-agent research pass
# (2026-09-01) found no support for one: no production multi-agent framework
# (LangGraph/AutoGen/CrewAI/OpenAI Agents SDK/Google ADK) enforces a
# zero-execution orchestrator, Anthropic's own Claude Code sub-agents docs
# name 4 explicit conditions favoring main-thread execution (iteration, shared
# context, quick targeted change, latency), and this repo's own recorded
# incident history has zero under-delegation incidents against several
# documented over-delegation ones. See the plan addendum this gate was built
# from for the full citation trail.
#
# OPT-IN, OFF BY DEFAULT: no-op unless MH_MAIN_WRITE_BUDGET is a positive
# integer. A Bash `export` inside a Claude Code session does NOT reach this
# hook's subprocess -- hooks are spawned by the host process, not the Bash
# tool's shell. Set it by relaunching as `MH_MAIN_WRITE_BUDGET=1 claude`, or
# via `~/.claude/settings.json`'s `env` block (restart required either way).
#
# THRESHOLD IS PROVISIONAL, NOT DERIVED. Sampled main_writes maxima the day
# this shipped: 488, 252, 2 (n=3, one day of data, the field itself one day
# old). 150 sits below both heavy sessions so it can actually fire, and well
# above the light one -- a starting point for collecting more data, not a
# conclusion drawn from it. Revisit once nudge-compliance.jsonl accumulates a
# real baseline.
#
# LATCH, BY DESIGN: main_writes is session-cumulative and monotonic (re-derived
# from the whole transcript once per Stop, not per tool call), so the count is
# always "as of the last completed turn" and, once the budget is crossed, this
# asks on every subsequent main write for the rest of the session. Silence it
# with Claude Code's own "always allow" (session-wide -- disarms this gate for
# the rest of the session too, not just the current call). Non-latching
# alternative, same file/pass/staleness, no new state -- swap the jq tail for
# a last-two-rows delta instead of a running max:
#   | sort_by(.main_writes) | ((.[-1].main_writes // 0) - (.[-2].main_writes // 0))
# which reads "writes in the last completed turn" instead of "writes this
# session." Ships off -- the cumulative-budget shape was asked for explicitly.
#
# MIRROR-IMAGE BLIND SPOT: because the count only advances at Stop (once per
# turn, not per tool call), a session that does its hoarding within one or two
# very large turns crosses the budget with zero asks until that turn ends --
# this gate is least sensitive to exactly the worst-case shape it exists to
# catch. Not fixable without re-deriving from the transcript per call, which
# was rejected on measured latency (a 15MB transcript scan vs. a ~10ms metrics
# read) -- disclosed limitation, not a silent one.
#
# WORKTREE-GUARD INCOMPATIBILITY (deliberate, not an oversight): if
# MH_GUARDED_WORKSPACE is set, this gate no-ops entirely, unconditionally,
# before any other check. dispatch-pretooluse.py discards updatedInput from
# EVERY matched gate the instant ANY gate's merged decision reaches "ask" (a
# rank comparison, not something table order can fix) -- so once this gate
# latches, worktree-guard.py's auto-redirect into a session worktree would be
# silently dropped for the rest of the session if both were active together.
# The redirect matters more than the nudge; document the incompatibility, do
# not try to make both work at once.
#
# Overlaps hooks/advisory/flow-nudge.sh's delegation-ratio nudge (GH #120) at
# a more interruptive tier -- one more reason the default is off.
#
# FUTURE DIRECTION, NOT BUILT: a write:dispatch RATIO gate (main_writes vs.
# main_dispatches, both already in the same nudge-compliance.jsonl row) would
# be more meaningful than an absolute-count budget -- 251 writes alongside 77
# dispatches isn't the same signal as 251 alongside 0 -- but needs a second
# tuning knob and even less real data exists to set it from. Not this pass.
set -uo pipefail

# 1. Worktree-guard bail. Must be first, before touching stdin.
[[ -z "${MH_GUARDED_WORKSPACE:-}" ]] || exit 0

# 2. Hottest-matcher fast path. Bail before reading stdin or spawning anything.
budget="${MH_MAIN_WRITE_BUDGET:-}"
[[ -n "$budget" ]] || exit 0
if ! [[ "$budget" =~ ^[1-9][0-9]*$ ]]; then
  echo "[mh:gate] MH_MAIN_WRITE_BUDGET='$budget' is not a positive integer -- main-write-budget gate off (no default is assumed)" >&2
  exit 0
fi

# 3. Portability guard (#93 convention): announced fail-open.
command -v jq >/dev/null 2>&1 || {
  echo "[mh:gate] jq not found -- main-write-budget gate cannot run; allowing" >&2
  exit 0
}

payload=$(cat)

# 4. Subagent -> allow, unconditionally. agent_id present == subagent
#    (agent-recursion-guard.sh / task-complete-separation.sh discriminant;
#    agent_type is WRONG here -- it is also set for a top-level `claude --agent`).
#    A subagent's writes are neither counted against main's budget nor gated
#    by it: dispatched-subagent Write/Edit stays unrestricted, per this
#    repo's own dispatch doctrine.
[[ -z "$(jq -r '.agent_id // empty' <<<"$payload" 2>/dev/null)" ]] || exit 0

sid=$(jq -r '.session_id // empty' <<<"$payload" 2>/dev/null)
[[ -n "$sid" ]] || exit 0          # no session key -> cannot look up -> allow

mfile="${MH_NUDGE_METRICS_FILE:-$HOME/.local/share/kbg/metrics/nudge-compliance.jsonl}"
[[ -f "$mfile" ]] || exit 0        # no metrics yet -> allow

# 5. Cumulative main_writes for THIS session. Filter to only this session's
#    own rows FIRST (grep -F on the literal `"session_id":"$sid"` JSON
#    substring -- nudge-compliance-tracker.sh's own `jq -nRc` emits compact
#    JSON, no space after the colon), THEN cap with `tail -n 2000` on the
#    already-filtered result -- a single session's own row count is
#    inherently small (bounded by its own Stop-event count, not by how many
#    OTHER sessions ran), so filtering before capping is both cheaper and
#    correct. Filtering by FILE POSITION first (the original `tail -n 2000
#    "$mfile" | jq ...` shape) was a real bug (deep-audit, 2026-09-01,
#    reproduced against a fixture): a dormant session's own last row can fall
#    outside the tail window once OTHER sessions keep appending after it
#    stopped, silently under-counting a real budget crossing. Not live
#    against the real file today (~660 lines) -- live in roughly 1-2 weeks
#    at the observed ~250 rows/day growth rate with no rotation. The jq-level
#    `select(.session_id == $sid ...)` stays as the authoritative correctness
#    check; the grep is a cheap pre-filter, not a replacement for it.
#    -nRr, not -nr: without -R, `inputs` yields parsed objects, fromjson
#    throws, `try` swallows it, and this silently returns 0 forever. `try
#    fromjson` per nudge-compliance-tracker.sh's own idiom: one
#    truncated/malformed line must not kill the whole lookup.
writes=$(grep -F "\"session_id\":\"$sid\"" "$mfile" 2>/dev/null | tail -n 2000 | jq -nRr --arg sid "$sid" '
  [ inputs | try (fromjson | select(.session_id == $sid and (.main_writes | type == "number"))) ]
  | (max_by(.main_writes).main_writes // 0)
' 2>/dev/null)
# Bounded digit count (deep-audit, 2026-09-01), not an unbounded ^[0-9]+$: the
# tracker only ever emits small non-negative integers, but an unbounded regex
# would pass a hand-corrupted 19+ digit value straight into the bash
# arithmetic below, which silently truncates at 64 bits and can evaluate as
# under-budget with no error. 15 digits stays safely inside range for any
# real value this gate will ever see.
[[ "$writes" =~ ^[0-9]{1,15}$ ]] || exit 0   # malformed/absent -> allow

(( writes >= budget )) || exit 0

# 6. Ask. Same JSON shape as lib/_hook_output.py's emit_ask() -- inlined via
#    heredoc rather than spawning python3 for a fixed-shape object on the
#    hottest-matched gate in the table.
cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"main-write-budget: this session's main thread has made $writes inline Write/Edit/NotebookEdit calls as of the last completed turn (budget: $budget). Consider dispatching this to a subagent instead. If inline is correct, name which of the 9 inline-wins clauses applies (skills/workflow/orchestrate/reference.md) and approve. Subagent writes are unaffected by this gate."}}
EOF
exit 0
