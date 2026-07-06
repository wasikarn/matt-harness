#!/usr/bin/env bash
# learn-nudge unit tests: simulates SessionEnd JSON payloads pointing at a
# fixture transcript, asserts stderr output (nudge fired) vs silence (nudge
# skipped) and that stdout is ALWAYS empty (SessionEnd stdout is discarded —
# a hook that wrote a nudge there would be dead-at-birth). The hook never
# blocks (SessionEnd has no decision control), so all tests expect exit 0.
# Run standalone: bash hooks/tests/test-learn-nudge.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/hooks/advisory/learn-nudge.sh"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/kbg-learn-nudge-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

# Write a fixture transcript with N "type":"user" lines (mixed with some
# assistant lines, matching real transcript shape — user-turn count includes
# tool-result turns, which are also type:"user").
make_transcript() {
  local path="$1" n="$2" i
  : > "$path"
  for ((i = 0; i < n; i++)); do
    echo '{"type":"user","message":{"role":"user","content":"hi"}}' >> "$path"
  done
  echo '{"type":"assistant","message":{"role":"assistant","content":"ok"}}' >> "$path"
}

session_end_payload() {
  local transcript="$1" reason="${2:-other}"
  python3 -c '
import sys, json
print(json.dumps({
    "session_id": "test-session",
    "transcript_path": sys.argv[1],
    "cwd": "/tmp",
    "hook_event_name": "SessionEnd",
    "reason": sys.argv[2],
}))
' "$transcript" "$reason"
}

# Expect the hook to FIRE (stderr non-empty, stdout empty, exit 0).
test_nudge() {
  local desc="$1" payload="$2"
  local out err rc
  out=$(echo "$payload" | bash "$HOOK" 2>"$TMP/stderr")
  rc=$?
  err=$(cat "$TMP/stderr")
  if [[ "$rc" == "0" && -z "$out" && -n "$err" ]]; then
    echo "  ✅ NUDGE: $desc"
    pass=$((pass + 1))
  else
    echo "  ❌ NUDGE EXPECTED but rc=$rc stdout=<$out> stderr=<$(printf '%s' "$err" | head -c 80)>: $desc" >&2
    fail=$((fail + 1))
  fi
}

# Expect the hook to be SILENT (stderr empty, stdout empty, exit 0).
test_silent() {
  local desc="$1" payload="$2"
  local out err rc
  out=$(echo "$payload" | bash "$HOOK" 2>"$TMP/stderr")
  rc=$?
  err=$(cat "$TMP/stderr")
  if [[ "$rc" == "0" && -z "$out" && -z "$err" ]]; then
    echo "  ✅ SILENT: $desc"
    pass=$((pass + 1))
  else
    echo "  ❌ SILENT EXPECTED but rc=$rc stdout=<$out> stderr=<$(printf '%s' "$err" | head -c 80)>: $desc" >&2
    fail=$((fail + 1))
  fi
}

echo "=== learn-nudge hook (SessionEnd) ==="
echo ""
echo "--- trivial sessions (must stay silent) ---"
make_transcript "$TMP/t0.jsonl" 0
test_silent "0 user turns" "$(session_end_payload "$TMP/t0.jsonl")"

make_transcript "$TMP/t2.jsonl" 2
test_silent "2 user turns (below default MIN_TURNS=3)" "$(session_end_payload "$TMP/t2.jsonl")"

echo ""
echo "--- substantive sessions (must fire nudge) ---"
make_transcript "$TMP/t3.jsonl" 3
test_nudge "3 user turns (at default MIN_TURNS threshold)" "$(session_end_payload "$TMP/t3.jsonl")"

make_transcript "$TMP/t20.jsonl" 20
test_nudge "20 user turns (well past threshold)" "$(session_end_payload "$TMP/t20.jsonl")"

echo ""
echo "--- malformed / missing input (must stay silent + exit 0) ---"
empty_out=$(echo "" | bash "$HOOK" 2>"$TMP/stderr")
empty_rc=$?
empty_err=$(cat "$TMP/stderr")
if [[ "$empty_rc" == "0" && -z "$empty_out" && -z "$empty_err" ]]; then
  echo "  ✅ SILENT: empty stdin"
  pass=$((pass + 1))
else
  echo "  ❌ SILENT EXPECTED but rc=$empty_rc stdout=<$empty_out> stderr=<$empty_err>: empty stdin" >&2
  fail=$((fail + 1))
fi

test_silent "no transcript_path field in payload" '{"session_id":"x","hook_event_name":"SessionEnd","reason":"other"}'
test_silent "transcript_path points to nonexistent file" "$(session_end_payload "$TMP/does-not-exist.jsonl")"

echo ""
echo "--- reason gate (resume/clear must stay silent regardless of turn count) ---"
make_transcript "$TMP/t20b.jsonl" 20
test_silent "reason=resume, 20 user turns (session is suspending, not closing out)" \
  "$(session_end_payload "$TMP/t20b.jsonl" "resume")"
test_silent "reason=clear, 20 user turns (frequent mid-work housekeeping, not a nudge moment)" \
  "$(session_end_payload "$TMP/t20b.jsonl" "clear")"
test_nudge "reason=logout, 20 user turns (real close-out, must still fire)" \
  "$(session_end_payload "$TMP/t20b.jsonl" "logout")"

echo ""
echo "--- KBG_LEARN_NUDGE_MIN_TURNS override ---"
make_transcript "$TMP/t1.jsonl" 1
out=$(echo "$(session_end_payload "$TMP/t1.jsonl")" | KBG_LEARN_NUDGE_MIN_TURNS=1 bash "$HOOK" 2>"$TMP/stderr")
rc=$?
err=$(cat "$TMP/stderr")
if [[ "$rc" == "0" && -z "$out" && -n "$err" ]]; then
  echo "  ✅ NUDGE: 1 user turn with MIN_TURNS=1 override"
  pass=$((pass + 1))
else
  echo "  ❌ NUDGE EXPECTED but rc=$rc stdout=<$out> stderr=<$err>: 1 user turn with MIN_TURNS=1 override" >&2
  fail=$((fail + 1))
fi

echo ""
total=$((pass + fail))
echo "=== $pass/$total passed ==="
[[ "$fail" -eq 0 ]] && exit 0 || exit 1
