#!/usr/bin/env bash
# Unit tests for hooks/sensors/codex-quota-{sensor,advisory}.{sh,py}.
# Advisory-only pair: sensor records a Codex CLI usage-limit/rate-limit
# failure (PostToolUseFailure/Bash), advisory warns on the next Codex Bash
# call while the record is fresh (PreToolUse/Bash). Neither ever blocks.
# Run standalone: bash tests/hooks/test-codex-quota.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SENSOR="$ROOT/hooks/sensors/codex-quota-sensor.sh"
ADVISORY="$ROOT/hooks/sensors/codex-quota-advisory.sh"

pass=0
fail=0
ok()  { pass=$((pass + 1)); echo "PASS: $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: $1" >&2; }

failure_payload() {
  python3 -c 'import json, sys; print(json.dumps({"hook_event_name": "PostToolUseFailure", "tool_name": "Bash", "tool_input": {"command": sys.argv[1]}, "tool_use_id": "toolu_test", "error": sys.argv[2]}))' "$1" "$2"
}

pretooluse_payload() {
  python3 -c 'import json, sys; print(json.dumps({"hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": {"command": sys.argv[1]}}))' "$1"
}

STATE_DIR=$(mktemp -d)
trap '[ -n "$STATE_DIR" ] && rm -rf "$STATE_DIR" 2>/dev/null || true' EXIT
STATE="$STATE_DIR/state.json"

# --- a non-Codex command failing with quota-shaped text is ignored ---
out=$(failure_payload "npm install" "quota exceeded" | bash "$SENSOR" "$STATE")
if [ -z "$out" ] && [ ! -f "$STATE" ]; then
  ok "non-codex command failure never records, regardless of error text"
else
  bad "expected no output and no state file for a non-codex command, got out='$out' state_exists=$([ -f "$STATE" ] && echo yes || echo no)"
fi

# --- a codex command failing with a non-quota error is ignored ---
out=$(failure_payload "codex exec 'do the thing'" "some unrelated network error" | bash "$SENSOR" "$STATE")
if [ -z "$out" ] && [ ! -f "$STATE" ]; then
  ok "codex command failing on a non-quota error never records"
else
  bad "expected no state file for a non-quota codex failure, got out='$out'"
fi

# --- a codex command failing with a quota-shaped error records state, never blocks ---
out=$(failure_payload "codex exec 'do the thing'" "Usage limit reached, try again at Sep 26th" | bash "$SENSOR" "$STATE")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ] && [ -f "$STATE" ]; then
  ok "codex + quota-shaped failure records state and exits 0 with no output (sensor never itself warns)"
else
  bad "expected exit 0, no output, and a written state file, got rc=$rc out='$out' state_exists=$([ -f "$STATE" ] && echo yes || echo no)"
fi

# --- advisory warns on the next codex Bash call while the record is fresh ---
out=$(pretooluse_payload "codex exec 'retry'" | bash "$ADVISORY" "$STATE")
rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | /usr/bin/grep -q 'mh-codex-quota-advisory'; then
  ok "advisory warns on a fresh record, exit 0 (never blocks)"
else
  bad "expected an advisory nudge and exit 0, got rc=$rc out='$out'"
fi
if echo "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d["hookSpecificOutput"]["hookEventName"] == "PreToolUse" and "additionalContext" in d["hookSpecificOutput"] else 1)'; then
  ok "advisory payload is additionalContext-only, no permissionDecision (never denies)"
else
  bad "expected hookSpecificOutput.additionalContext with no permissionDecision, got: $out"
fi

# --- advisory stays silent for a non-codex command even with a fresh record ---
out=$(pretooluse_payload "npm test" | bash "$ADVISORY" "$STATE")
if [ -z "$out" ]; then
  ok "advisory ignores a non-codex command even while a record exists"
else
  bad "expected no output for a non-codex command, got out='$out'"
fi

# --- advisory self-clears a stale (past-TTL) record instead of warning forever ---
# TTL=-1 guarantees staleness regardless of clock timing (age is always >= 0 > -1).
payload=$(pretooluse_payload "codex exec 'again'")
out=$(echo "$payload" | MH_CODEX_QUOTA_TTL_SECONDS=-1 bash "$ADVISORY" "$STATE")
if [ -z "$out" ] && [ ! -f "$STATE" ]; then
  ok "advisory treats a record older than TTL as stale, removes it, and stays silent"
else
  bad "expected a negative TTL to make any existing record immediately stale, got out='$out' state_exists=$([ -f "$STATE" ] && echo yes || echo no)"
fi

echo
echo "codex-quota tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
