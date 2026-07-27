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
# Markers AND a real content token: asserting only the open/close markers would
# pass on an empty/rotted injection (silent doctrine-content rot). "Decision-sizing
# triad" is Rule 1's heading in docs/METHODOLOGY.md — its presence proves the
# body was injected, not just the wrapper.
[[ "$rc" == "0" ]] && echo "$out" | /usr/bin/grep -q '<!-- kbg:doctrine-bootstrap -->' \
  && echo "$out" | /usr/bin/grep -q '<!-- /kbg:doctrine-bootstrap -->' \
  && echo "$out" | /usr/bin/grep -q 'Decision-sizing triad' && ok=1 || ok=0
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

# Adversarial: malformed (non-JSON) transcript content. The jq `try fromjson`
# filter skips unparseable lines → usage is null → no row. Must fail safe.
fake_home=$(mktemp -d)
transcript=$(mktemp)
printf 'this is not json\n{ broken\nalso not json\n' > "$transcript"
payload=$(python3 -c 'import json,sys; print(json.dumps({"transcript_path": sys.argv[1], "session_id": "test-session"}))' "$transcript")
out=$(printf '%s' "$payload" | HOME="$fake_home" bash "$COST_TRACKER" 2>/dev/null)
rc=$?
metrics_file="$fake_home/.local/share/kbg/metrics/costs.jsonl"
[[ "$rc" == "0" && "$out" == "$payload" && ! -f "$metrics_file" ]] && ok=1 || ok=0
assert "fails safe (exit 0, no metrics row) for a malformed-JSON transcript" "$ok"
rm -rf "$fake_home" "$transcript"

# Adversarial: assistant line carries usage: null. The jq
# `select((.message // {}).usage != null)` filter drops it → usage is null → no row.
fake_home=$(mktemp -d)
transcript=$(mktemp)
python3 -c '
import json
line = {"type": "assistant", "message": {"model": "claude-sonnet-5", "usage": None}}
print(json.dumps(line))
' > "$transcript"
payload=$(python3 -c 'import json,sys; print(json.dumps({"transcript_path": sys.argv[1], "session_id": "test-session"}))' "$transcript")
out=$(printf '%s' "$payload" | HOME="$fake_home" bash "$COST_TRACKER" 2>/dev/null)
rc=$?
metrics_file="$fake_home/.local/share/kbg/metrics/costs.jsonl"
[[ "$rc" == "0" && "$out" == "$payload" && ! -f "$metrics_file" ]] && ok=1 || ok=0
assert "fails safe (exit 0, no metrics row) when usage is null" "$ok"
rm -rf "$fake_home" "$transcript"

# Adversarial: multi-line transcript (two assistant lines) must aggregate into ONE
# compact JSONL row with summed tokens, not one row per line.
fake_home=$(mktemp -d)
transcript=$(mktemp)
python3 -c '
import json
for tok_in, tok_out in [(100, 50), (200, 80)]:
    line = {"type": "assistant", "message": {"model": "claude-sonnet-5",
      "usage": {"input_tokens": tok_in, "output_tokens": tok_out,
                "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0}}}
    print(json.dumps(line))
' > "$transcript"
payload=$(python3 -c 'import json,sys; print(json.dumps({"transcript_path": sys.argv[1], "session_id": "multi"}))' "$transcript")
out=$(printf '%s' "$payload" | HOME="$fake_home" bash "$COST_TRACKER" 2>/dev/null)
rc=$?
metrics_file="$fake_home/.local/share/kbg/metrics/costs.jsonl"
row=$(tail -1 "$metrics_file" 2>/dev/null)
# Exactly one row, input_tokens summed to 300 (100+200), output_tokens summed to 130.
[[ "$rc" == "0" && -f "$metrics_file" \
  && "$(wc -l < "$metrics_file" | tr -d ' ')" == "1" ]] \
  && printf '%s' "$row" | /usr/bin/grep -q '"session_id":"multi"' \
  && printf '%s' "$row" | /usr/bin/grep -q '"input_tokens":300' \
  && printf '%s' "$row" | /usr/bin/grep -q '"output_tokens":130' \
  && printf '%s' "$row" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null && ok=1 || ok=0
assert "aggregates a multi-line transcript into one summed JSONL cost row" "$ok"
rm -rf "$fake_home" "$transcript"

# Adversarial: multi-MODEL transcript (two assistant lines, different `.message.model`)
# must write ONE row PER MODEL, each model_scoped:true, each carrying only that
# model's own tokens — not one summed row tagged with whichever model was last used
# (the pre-fix behavior this rewrite replaced).
fake_home=$(mktemp -d)
transcript=$(mktemp)
python3 -c '
import json
for model, tok_in, tok_out in [("claude-opus-4-8", 100, 50), ("claude-sonnet-5", 200, 80)]:
    line = {"type": "assistant", "message": {"model": model,
      "usage": {"input_tokens": tok_in, "output_tokens": tok_out,
                "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0}}}
    print(json.dumps(line))
' > "$transcript"
payload=$(python3 -c 'import json,sys; print(json.dumps({"transcript_path": sys.argv[1], "session_id": "multi-model"}))' "$transcript")
out=$(printf '%s' "$payload" | HOME="$fake_home" bash "$COST_TRACKER" 2>/dev/null)
rc=$?
metrics_file="$fake_home/.local/share/kbg/metrics/costs.jsonl"
opus_row=$(/usr/bin/grep '"model":"claude-opus-4-8"' "$metrics_file" 2>/dev/null)
sonnet_row=$(/usr/bin/grep '"model":"claude-sonnet-5"' "$metrics_file" 2>/dev/null)
[[ "$rc" == "0" && -f "$metrics_file" \
  && "$(wc -l < "$metrics_file" | tr -d ' ')" == "2" ]] \
  && printf '%s' "$opus_row" | /usr/bin/grep -q '"model_scoped":true' \
  && printf '%s' "$opus_row" | /usr/bin/grep -q '"input_tokens":100' \
  && printf '%s' "$opus_row" | /usr/bin/grep -q '"output_tokens":50' \
  && printf '%s' "$sonnet_row" | /usr/bin/grep -q '"model_scoped":true' \
  && printf '%s' "$sonnet_row" | /usr/bin/grep -q '"input_tokens":200' \
  && printf '%s' "$sonnet_row" | /usr/bin/grep -q '"output_tokens":80' \
  && printf '%s' "$opus_row" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null \
  && printf '%s' "$sonnet_row" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null && ok=1 || ok=0
assert "multi-model transcript writes one model_scoped row per model with that model's own tokens" "$ok"
rm -rf "$fake_home" "$transcript"

echo ""
total=$((pass + fail))
echo "=== $pass/$total passed ==="
[[ "$fail" -eq 0 ]] && exit 0 || exit 1
