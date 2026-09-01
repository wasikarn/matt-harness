#!/usr/bin/env bash
# Behavioral tests for hooks/gates/main-write-budget.sh. Covers the opt-in
# off-by-default no-op, the worktree-guard compatibility bail (must run
# before any budget check), the subagent bypass, the >= boundary, the
# session-id scoping (max_by across out-of-order/interleaved rows, not
# first/last match), the malformed-metrics-file resilience (one truncated
# JSONL line must not kill the whole lookup -- `jq -nRr`, not `jq -nr`), and
# the invalid-budget-value fail-open (never silently falls back to a default).
# Every case drives MH_NUDGE_METRICS_FILE at a throwaway fixture file --
# never the operator's real nudge-compliance.jsonl.
# Run standalone: bash tests/hooks/test-main-write-budget.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/hooks/gates/main-write-budget.sh"

pass=0
fail=0

check() { # check <desc> <ok:0|1>
  if [ "$2" -eq 0 ]; then echo "  ✅ $1"; pass=$((pass + 1))
  else echo "  ❌ $1" >&2; fail=$((fail + 1)); fi
}

payload() { # payload <session_id> [extra_json_fields_no_braces]
  local sid="$1" extra="${2:-}"
  if [ -n "$extra" ]; then
    printf '{"session_id":"%s","tool_name":"Write","%s}' "$sid" "$extra"
  else
    printf '{"session_id":"%s","tool_name":"Write"}' "$sid"
  fi
}

row() { # row <session_id> <main_writes>
  printf '{"session_id":"%s","main_writes":%s}\n' "$1" "$2"
}

echo "=== main-write-budget gate ==="
cd "$ROOT" || exit 1
unset MH_GUARDED_WORKSPACE MH_MAIN_WRITE_BUDGET 2>/dev/null || true

FIXDIR="$(mktemp -d)"
trap 'trash "$FIXDIR" 2>/dev/null || true' EXIT
MFILE="$FIXDIR/nudge-compliance.jsonl"

run_gate() { # run_gate <json_payload> -- runs with MH_NUDGE_METRICS_FILE=$MFILE
  MH_NUDGE_METRICS_FILE="$MFILE" bash "$GATE" <<<"$1"
}

is_ask() { # is_ask <output> -> 0 if ask JSON present
  echo "$1" | /usr/bin/grep -q '"permissionDecision":"ask"'
}

# 1. Budget unset -> no-op regardless of main_writes.
row "sid-1" 999 > "$MFILE"
out=$(unset MH_MAIN_WRITE_BUDGET; run_gate "$(payload sid-1)"); rc=$?
ok=1; [ -z "$out" ] && [ "$rc" -eq 0 ] && ok=0
check "budget unset -> no output, exit 0" "$ok"

# 2. Worktree-guard bail must run before any budget check, even with a huge
#    over-budget count. Run in a subshell so MH_GUARDED_WORKSPACE never leaks.
row "sid-2" 999 > "$MFILE"
out=$(
  export MH_GUARDED_WORKSPACE=/tmp/fake-guarded-workspace
  export MH_MAIN_WRITE_BUDGET=100
  run_gate "$(payload sid-2)"
)
rc=$?
ok=1; [ -z "$out" ] && [ "$rc" -eq 0 ] && ok=0
check "MH_GUARDED_WORKSPACE set -> bail before budget check, no output" "$ok"

# 3. Positive control: over budget, no agent_id -> ask fires with proper JSON shape.
row "sid-3" 150 > "$MFILE"
out=$(MH_MAIN_WRITE_BUDGET=100 run_gate "$(payload sid-3)"); rc=$?
ok=0
[ "$rc" -eq 0 ] || ok=1
echo "$out" | jq -e '.hookSpecificOutput.permissionDecision == "ask"' >/dev/null 2>&1 || ok=1
check "over budget, main payload -> ask with correct JSON shape" "$ok"

# 4. Subagent bypass: agent_id present -> no ask even over budget.
row "sid-4" 150 > "$MFILE"
out=$(MH_MAIN_WRITE_BUDGET=100 run_gate "$(payload sid-4 '"agent_id":"agent-123"')"); rc=$?
ok=1; [ -z "$out" ] && [ "$rc" -eq 0 ] && ok=0
check "agent_id present -> subagent bypass, no output" "$ok"

# 5. Under budget -> no ask.
row "sid-5" 50 > "$MFILE"
out=$(MH_MAIN_WRITE_BUDGET=100 run_gate "$(payload sid-5)"); rc=$?
ok=1; [ -z "$out" ] && [ "$rc" -eq 0 ] && ok=0
check "under budget -> no output" "$ok"

# 6. Exactly at budget -> ask (>=, not >).
row "sid-6" 100 > "$MFILE"
out=$(MH_MAIN_WRITE_BUDGET=100 run_gate "$(payload sid-6)"); rc=$?
ok=1; is_ask "$out" && [ "$rc" -eq 0 ] && ok=0
check "main_writes == budget exactly -> ask (>= boundary)" "$ok"

# 7. Fixture has rows, but none for this session -> reads as 0 -> no ask.
row "sid-other" 999 > "$MFILE"
out=$(MH_MAIN_WRITE_BUDGET=100 run_gate "$(payload sid-7)"); rc=$?
ok=1; [ -z "$out" ] && [ "$rc" -eq 0 ] && ok=0
check "unrecognized session_id -> no output (reads as 0)" "$ok"

# 8. Metrics file path does not exist at all -> no ask, no crash.
out=$(MH_MAIN_WRITE_BUDGET=100 MH_NUDGE_METRICS_FILE="$FIXDIR/does-not-exist.jsonl" bash "$GATE" <<<"$(payload sid-8)"); rc=$?
ok=1; [ -z "$out" ] && [ "$rc" -eq 0 ] && ok=0
check "metrics file missing -> no output, exit 0, no crash" "$ok"

# 9. Payload has no session_id key at all -> no ask.
row "sid-9" 999 > "$MFILE"
out=$(MH_MAIN_WRITE_BUDGET=100 run_gate '{"tool_name":"Write"}'); rc=$?
ok=1; [ -z "$out" ] && [ "$rc" -eq 0 ] && ok=0
check "no session_id key in payload -> no output" "$ok"

# 10. Multiple rows, out of chronological order -> uses max, not first/last.
{ row "sid-10" 60; row "sid-10" 150; row "sid-10" 90; } > "$MFILE"
out=$(MH_MAIN_WRITE_BUDGET=100 run_gate "$(payload sid-10)"); rc=$?
ok=1
is_ask "$out" && [ "$rc" -eq 0 ] && echo "$out" | /usr/bin/grep -q '150' && ok=0
check "out-of-order rows -> ask using max_by (150), not first/last match" "$ok"

# 11. Interleaved rows for a different session at 999 must not leak into target.
{ row "sid-11" 40; row "sid-leak" 999; row "sid-11" 60; } > "$MFILE"
out=$(MH_MAIN_WRITE_BUDGET=100 run_gate "$(payload sid-11)"); rc=$?
ok=1; [ -z "$out" ] && [ "$rc" -eq 0 ] && ok=0
check "interleaved different-session rows -> no leakage into target session count" "$ok"

# 12. First line truncated/garbage JSON, second line valid -> ask still fires.
#     Pins `try fromjson` specifically: one malformed line must not kill the
#     whole lookup (the -R flag itself is already exercised by every other
#     ask-case above -- without it every lookup silently returns 0 forever).
{
  printf '{"session_id": "sid1", "main\n'
  row "sid-12" 150
} > "$MFILE"
out=$(MH_MAIN_WRITE_BUDGET=100 run_gate "$(payload sid-12)"); rc=$?
ok=1; is_ask "$out" && [ "$rc" -eq 0 ] && ok=0
check "malformed first JSONL line -> ask still fires (try fromjson resilience)" "$ok"

# 13. Invalid budget values must turn the gate off, never fall back to a default.
row "sid-13" 999 > "$MFILE"
for badbudget in abc 0 -5; do
  out=$(MH_MAIN_WRITE_BUDGET="$badbudget" run_gate "$(payload sid-13)" 2>/dev/null); rc=$?
  ok=1; [ -z "$out" ] && [ "$rc" -eq 0 ] && ok=0
  check "MH_MAIN_WRITE_BUDGET='$badbudget' -> gate off, no output" "$ok"
done

# 14. Ask reason text contains the literal phrase "last completed turn".
row "sid-14" 150 > "$MFILE"
out=$(MH_MAIN_WRITE_BUDGET=100 run_gate "$(payload sid-14)"); rc=$?
ok=0
[ "$rc" -eq 0 ] || ok=1
echo "$out" | jq -e -r '.hookSpecificOutput.permissionDecisionReason' 2>/dev/null | /usr/bin/grep -q 'last completed turn' || ok=1
check "ask reason contains 'last completed turn'" "$ok"

# 15. tool_name NotebookEdit instead of Write/Edit -> ask still fires (gate
#     doesn't branch on tool_name; matcher parity is enforced by table registration).
row "sid-15" 150 > "$MFILE"
out=$(MH_MAIN_WRITE_BUDGET=100 run_gate '{"session_id":"sid-15","tool_name":"NotebookEdit"}'); rc=$?
ok=1; is_ask "$out" && [ "$rc" -eq 0 ] && ok=0
check "tool_name=NotebookEdit -> ask still fires" "$ok"

echo ""
echo "=== $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
