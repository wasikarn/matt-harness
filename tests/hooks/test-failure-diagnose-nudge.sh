#!/usr/bin/env bash
# Unit tests for hooks/sensors/failure-diagnose-nudge.{sh,py} (GH #153).
# Advisory PostToolUseFailure(Bash) sensor: never blocks (always exit 0), emits a
# diagnose-before-retry nudge on a real Bash failure, capped at 1 per distinct
# command per session.
# Run standalone: bash tests/hooks/test-failure-diagnose-nudge.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SENSOR="$ROOT/hooks/sensors/failure-diagnose-nudge.sh"

pass=0
fail=0
ok()  { pass=$((pass + 1)); echo "PASS: $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: $1" >&2; }

# A PostToolUse(Bash)-success-shaped payload -- used only as a "wrong shape"
# fixture below (hooks.json no longer routes this event to the sensor at
# all, deep-audit 2026-09-07, but is_failure() must still stay false-safe on
# any shape that isn't PostToolUseFailure).
posttooluse_payload() {
  python3 -c 'import json, sys; print(json.dumps({"tool_name": "Bash", "tool_input": {"command": sys.argv[1]}, "tool_response": {"exit_code": int(sys.argv[2])}}))' "$1" "$2"
}

# The REAL shape of a failing Bash call, per the installed Claude Code binary's
# own hook-input schema (Ioe in the 2.1.263 bundle): PostToolUseFailure has NO
# tool_response field at all -- exit_code never appears anywhere in it. It has
# hook_event_name, tool_name, tool_input, tool_use_id, and error (a string).
# Deep-audit 2026-09-07: PostToolUse(Bash) never fires for a real nonzero
# shell exit in this CC version -- confirmed by a live in-session debug dump
# that never received a single invocation on a genuine `ls <missing-path>`
# failure. This is the only shape hooks.json now routes to the sensor.
posttoolusefailure_payload() {
  python3 -c 'import json, sys; print(json.dumps({"hook_event_name": "PostToolUseFailure", "tool_name": "Bash", "tool_input": {"command": sys.argv[1]}, "tool_use_id": "toolu_test", "error": sys.argv[2]}))' "$1" "$2"
}

STATE_DIR=$(mktemp -d)
trap '[ -n "$STATE_DIR" ] && trash "$STATE_DIR" 2>/dev/null || true' EXIT
STATE="$STATE_DIR/state.json"

# --- a non-PostToolUseFailure-shaped payload never nudges, regardless of
# its exit_code -- is_failure() keys only off hook_event_name now ---
out=$(posttooluse_payload "ls -la" 0 | bash "$SENSOR" "$STATE")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  ok "non-PostToolUseFailure shape (exit 0) -- no nudge, exit 0"
else
  bad "PostToolUse-success shape should produce no output and exit 0, got rc=$rc out='$out'"
fi

out=$(posttooluse_payload "make build" 1 | bash "$SENSOR" "$STATE")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  ok "non-PostToolUseFailure shape (exit 1) -- still no nudge, exit 0 (dead PostToolUse branch stays removed)"
else
  bad "PostToolUse-shaped payload should never nudge post-removal, got rc=$rc out='$out'"
fi

# --- the REAL failure shape (PostToolUseFailure, no tool_response/exit_code
# at all) nudges -- this is what a genuine Bash failure sends ---
out=$(posttoolusefailure_payload "make build" "Command failed with exit code 1" | bash "$SENSOR" "$STATE")
rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | /usr/bin/grep -q 'mh-failure-diagnose-nudge'; then
  ok "PostToolUseFailure shape -- nudge emitted, exit 0 (never blocks)"
else
  bad "PostToolUseFailure shape should emit the nudge and exit 0, got rc=$rc out='$out'"
fi
if echo "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d["hookSpecificOutput"]["hookEventName"] == "PostToolUseFailure" else 1)'; then
  ok "PostToolUseFailure payload echoes hookEventName: PostToolUseFailure"
else
  bad "expected hookSpecificOutput.hookEventName == PostToolUseFailure, got: $out"
fi

# --- a user-interrupted command (is_interrupt: true) is not a failure to
# diagnose: no nudge, and it must not spend the command's cap (GH #331) ---
payload=$(posttoolusefailure_payload "interrupted-cmd" "Interrupted by user")
payload=$(python3 -c 'import json,sys; d=json.loads(sys.argv[1]); d["is_interrupt"]=True; print(json.dumps(d))' "$payload")
out=$(echo "$payload" | bash "$SENSOR" "$STATE")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  ok "is_interrupt: true -- no nudge, exit 0 (GH #331)"
else
  bad "is_interrupt: true should produce no output and exit 0, got rc=$rc out='$out'"
fi
out=$(posttoolusefailure_payload "interrupted-cmd" "Command failed" | bash "$SENSOR" "$STATE")
if echo "$out" | /usr/bin/grep -q 'mh-failure-diagnose-nudge'; then
  ok "an interrupt does not spend the command's cap -- a later real failure still nudges"
else
  bad "a real failure after an interrupt of the same command should still nudge, got '$out'"
fi

# --- cap enforcement: same command failing repeatedly stops nudging after CAP=1 ---
trash "$STATE" 2>/dev/null || true
nudge_count=0
for _ in 1 2 3 4 5; do
  out=$(posttoolusefailure_payload "flaky-cmd --retry" "Command failed" | bash "$SENSOR" "$STATE")
  echo "$out" | /usr/bin/grep -q 'mh-failure-diagnose-nudge' && nudge_count=$((nudge_count + 1))
done
if [ "$nudge_count" -eq 1 ]; then
  ok "cap enforcement: exactly 1 nudge across 5 identical failures (was uncapped in the trialed plugin)"
else
  bad "expected exactly 1 nudge across 5 identical failures, got $nudge_count"
fi

# --- a DIFFERENT failing command gets its own fresh cap ---
out=$(posttoolusefailure_payload "a-completely-different-command" "Command failed" | bash "$SENSOR" "$STATE")
if echo "$out" | /usr/bin/grep -q 'mh-failure-diagnose-nudge'; then
  ok "a different failing command is not affected by another command's exhausted cap"
else
  bad "a fresh distinct command should still nudge even after a different command's cap is exhausted"
fi

# --- unparseable stdin: fail-open, no crash, no nudge ---
out=$(printf 'not json at all' | bash "$SENSOR" "$STATE")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  ok "unparseable payload -- fails open silently, exit 0"
else
  bad "unparseable payload should fail open with no output, got rc=$rc out='$out'"
fi

# --- missing python3: fail-open with a stderr announcement (GH #93 posture) ---
# Payload written to a file and redirected (not piped from a live process):
# the sensor's python3-missing fast path never reads stdin at all, so a live
# upstream writer piping into it can hit a benign SIGPIPE race that pollutes
# the captured exit status -- redirecting from a file sidesteps that.
# A directory containing only a `bash` symlink, not a hardcoded OS path: macOS's
# /bin lacks python3 (Apple's stub lives in /usr/bin), but a usr-merged Linux
# distro symlinks /bin -> /usr/bin, so PATH=/bin still finds python3 there --
# confirmed live on Ubuntu 24.04 (readlink -f /bin -> /usr/bin).
STDERR_CAP="$STATE_DIR/stderr.txt"
NO_PYTHON3_PATH="$STATE_DIR/no-python3-bin"
mkdir -p "$NO_PYTHON3_PATH"
ln -sf "$(command -v bash)" "$NO_PYTHON3_PATH/bash"
posttoolusefailure_payload "make build" "Command failed" > "$STATE_DIR/payload.json"
out=$(PATH="$NO_PYTHON3_PATH" bash "$SENSOR" "$STATE" < "$STATE_DIR/payload.json" 2>"$STDERR_CAP")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ] && /usr/bin/grep -qi 'python3 not found' "$STDERR_CAP"; then
  ok "missing python3 -- fails open AND announces on stderr (GH #93 posture)"
else
  bad "missing python3 should fail open + announce, got rc=$rc out='$out' stderr='$(cat "$STDERR_CAP" 2>/dev/null)'"
fi

# --- default_state_path keys off the payload's own session_id, not just the
# env var -- a missing CLAUDE_CODE_SESSION_ID must not collapse every session
# onto one shared, never-reset counter file ---
FAKE_TMPDIR="$STATE_DIR/tmp-default"
mkdir -p "$FAKE_TMPDIR"
payload=$(posttoolusefailure_payload "default-path-cmd" "Command failed")
payload=$(python3 -c 'import json,sys; d=json.loads(sys.argv[1]); d["session_id"]="sess-xyz"; print(json.dumps(d))' "$payload")
out=$(
  unset CLAUDE_CODE_SESSION_ID
  export TMPDIR="$FAKE_TMPDIR"
  echo "$payload" | bash "$SENSOR"
)
rc=$?
expected_state="$FAKE_TMPDIR/mh-sensors/failure-nudge-sess-xyz.json"
if [ "$rc" -eq 0 ] && [ -f "$expected_state" ] && echo "$out" | /usr/bin/grep -q 'mh-failure-diagnose-nudge'; then
  ok "default_state_path uses the payload's session_id, staying session-scoped without the env var"
else
  bad "expected state file at $expected_state, got rc=$rc out='$out'"
fi

# --- locked() must actually provide mutual exclusion (Deep-audit 2026-09-07:
# load_counts/save_counts used to run as two separate, uncoordinated file
# opens, letting concurrent Bash completions interleave their read-modify-
# write and lose an increment). A natural-timing race across real subprocess
# launches did NOT reliably reproduce the interleave on this machine (process
# fork/exec overhead swamps the actual race window) -- tried and confirmed
# unreliable before writing this, so it is deliberately not the regression
# test. Instead: two child processes each hold locked() for a fixed sleep
# while recording their own [acquire, release] timestamps to a shared file;
# mutual exclusion holds iff neither interval overlaps the other. This is
# deterministic (no timing luck) and tests the actual property the fix
# provides, not a proxy for it.
LOCK_TEST_STATE="$STATE_DIR/lock-test-state.json"
LOCK_TEST_LOG="$STATE_DIR/lock-intervals.jsonl"
python3 - "$ROOT/hooks/sensors/failure-diagnose-nudge.py" "$LOCK_TEST_STATE" "$LOCK_TEST_LOG" <<'PYEOF'
import importlib.util, os, sys, time

sensor_path, state_path, log_path = sys.argv[1], sys.argv[2], sys.argv[3]
spec = importlib.util.spec_from_file_location("fdn", sensor_path)
fdn = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fdn)

def hold(tag):
    with fdn.locked(state_path):
        start = time.time()
        time.sleep(0.3)
        end = time.time()
    with open(log_path, "a") as f:
        f.write(f"{tag} {start} {end}\n")

# os.fork() (not multiprocessing.Process) -- macOS's default "spawn" start
# method needs to re-import __main__ from a real file path, which a script
# read from stdin doesn't have.
pids = []
for tag in ("A", "B"):
    pid = os.fork()
    if pid == 0:
        hold(tag)
        os._exit(0)
    pids.append(pid)
for pid in pids:
    os.waitpid(pid, 0)

with open(log_path) as f:
    rows = [line.split() for line in f if line.strip()]
intervals = {tag: (float(s), float(e)) for tag, s, e in rows}
(sa, ea), (sb, eb) = intervals["A"], intervals["B"]
overlap = sa < eb and sb < ea
sys.exit(1 if overlap else 0)
PYEOF
if [ "$?" -eq 0 ]; then
  ok "locked() provides real mutual exclusion: two holders' [acquire, release] intervals never overlap"
else
  bad "locked() failed to serialize -- two holders' intervals overlapped ($(cat "$LOCK_TEST_LOG" 2>/dev/null))"
fi

echo "failure-diagnose-nudge: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
