#!/usr/bin/env bash
# Session/Stop hook smoke tests: doctrine-bootstrap (SessionStart),
# command-root-anchor (SessionStart), cost-tracker (Stop). These hooks never
# block (no permissionDecision) — tests assert exit 0 + expected side effect
# (stdout injection / env-file append / metrics-file append), and that each
# fails safe (exit 0, no side effect) when its required env var is unset.
# Run standalone: bash hooks/tests/test-session-stop.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DOCTRINE="$ROOT/hooks/session/doctrine-bootstrap.sh"
ROOT_ANCHOR="$ROOT/hooks/session/command-root-anchor.sh"
COST_TRACKER="$ROOT/hooks/stop/cost-tracker.sh"

pass=0
fail=0

assert() {
  local desc="$1" ok="$2"
  if [[ "$ok" == "1" ]]; then
    echo "  ✅ $desc"
    pass=$((pass + 1))
  else
    echo "  ❌ $desc" >&2
    fail=$((fail + 1))
  fi
}

echo "=== doctrine-bootstrap hook (SessionStart) ==="

out=$(CLAUDE_PLUGIN_ROOT="$ROOT" bash "$DOCTRINE" 2>/dev/null)
rc=$?
[[ "$rc" == "0" ]] && echo "$out" | /usr/bin/grep -q '<!-- kbg:doctrine-bootstrap -->' \
  && echo "$out" | /usr/bin/grep -q '<!-- /kbg:doctrine-bootstrap -->' && ok=1 || ok=0
assert "injects METHODOLOGY.md wrapped in markers when plugin root is valid" "$ok"

out=$(env -u CLAUDE_PLUGIN_ROOT bash "$DOCTRINE" 2>/dev/null)
rc=$?
[[ "$rc" == "0" && -z "$out" ]] && ok=1 || ok=0
assert "fails safe (exit 0, silent) when CLAUDE_PLUGIN_ROOT is unset" "$ok"

out=$(CLAUDE_PLUGIN_ROOT="/nonexistent-plugin-root" bash "$DOCTRINE" 2>/dev/null)
rc=$?
[[ "$rc" == "0" && -z "$out" ]] && ok=1 || ok=0
assert "fails safe (exit 0, silent) when plugin root path doesn't exist" "$ok"

echo ""
echo "=== command-root-anchor hook (SessionStart) ==="

envfile=$(mktemp)
CLAUDE_PLUGIN_ROOT="/some/plugin/root/" CLAUDE_ENV_FILE="$envfile" bash "$ROOT_ANCHOR" 2>/dev/null
rc=$?
[[ "$rc" == "0" ]] && /usr/bin/grep -qx 'export KBG_PLUGIN_ROOT=/some/plugin/root' "$envfile" && ok=1 || ok=0
assert "strips trailing slash and appends export to CLAUDE_ENV_FILE" "$ok"
rm -f "$envfile"

envfile=$(mktemp)
env -u CLAUDE_PLUGIN_ROOT CLAUDE_ENV_FILE="$envfile" bash "$ROOT_ANCHOR" 2>/dev/null
rc=$?
[[ "$rc" == "0" && ! -s "$envfile" ]] && ok=1 || ok=0
assert "fails safe (exit 0, no append) when CLAUDE_PLUGIN_ROOT is unset" "$ok"
rm -f "$envfile"

CLAUDE_PLUGIN_ROOT="/some/plugin/root" env -u CLAUDE_ENV_FILE bash "$ROOT_ANCHOR" 2>/dev/null
rc=$?
[[ "$rc" == "0" ]] && ok=1 || ok=0
assert "fails safe (exit 0) when CLAUDE_ENV_FILE is unset" "$ok"

echo ""
echo "=== cost-tracker hook (Stop) ==="

fake_home=$(mktemp -d)
transcript=$(mktemp)
python3 -c '
import json
line = {"type": "assistant", "message": {"model": "claude-sonnet-5",
  "usage": {"input_tokens": 100, "output_tokens": 50,
            "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0}}}
print(json.dumps(line))
' > "$transcript"
payload=$(python3 -c 'import json,sys; print(json.dumps({"transcript_path": sys.argv[1], "session_id": "test-session"}))' "$transcript")
out=$(printf '%s' "$payload" | HOME="$fake_home" bash "$COST_TRACKER" 2>/dev/null)
rc=$?
metrics_file="$fake_home/.local/share/kbg/metrics/costs.jsonl"
# cost-tracker appends with `jq -c` → one compact JSON object per line (found
# 2026-07-03: the old pretty-printed format broke every line-oriented reader).
row=$(tail -1 "$metrics_file" 2>/dev/null)
[[ "$rc" == "0" && "$out" == "$payload" && -f "$metrics_file" ]] \
  && printf '%s' "$row" | /usr/bin/grep -q '"session_id":"test-session"' \
  && [[ "$(wc -l < "$metrics_file" | tr -d ' ')" == "1" ]] \
  && printf '%s' "$row" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null && ok=1 || ok=0
assert "echoes payload through + appends one compact JSONL cost row for a valid transcript" "$ok"
rm -rf "$fake_home" "$transcript"

fake_home=$(mktemp -d)
payload=$(python3 -c 'import json; print(json.dumps({"transcript_path": "/nonexistent/transcript.jsonl", "session_id": "test-session"}))')
out=$(printf '%s' "$payload" | HOME="$fake_home" bash "$COST_TRACKER" 2>/dev/null)
rc=$?
metrics_file="$fake_home/.local/share/kbg/metrics/costs.jsonl"
[[ "$rc" == "0" && "$out" == "$payload" && ! -f "$metrics_file" ]] && ok=1 || ok=0
assert "fails safe (exit 0, echoes payload, no metrics row) for a missing transcript" "$ok"
rm -rf "$fake_home"

echo ""
total=$((pass + fail))
echo "=== $pass/$total passed ==="
[[ "$fail" -eq 0 ]] && exit 0 || exit 1
