#!/usr/bin/env bash
# instructions-loaded-journal unit tests: simulates InstructionsLoaded JSON
# payloads and asserts one compact JSONL row lands per invocation, with the
# expected fields carried through. The hook has no decision control (its
# stdout is always empty/discarded), so every test checks the log file, not
# stdout, and every test expects exit 0.
# Run standalone: bash tests/hooks/test-instructions-loaded-journal.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/hooks/session/instructions-loaded-journal.sh"

pass=0
fail=0

TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT
LOG_FILE="$TMP_HOME/.local/share/kbg/metrics/instructions-loaded.jsonl"

run_hook() {
  local payload="$1"
  HOME="$TMP_HOME" bash -c "echo '$payload' | '$HOOK'"
}

echo "=== instructions-loaded-journal hook (InstructionsLoaded) ==="
echo ""

payload='{"session_id":"sess-1","cwd":"/repo","hook_event_name":"InstructionsLoaded","file_path":"/repo/CLAUDE.md","memory_type":"Project","load_reason":"session_start"}'
run_hook "$payload" >/tmp/il-stdout.$$ 2>/tmp/il-stderr.$$
rc=$?
stdout_content=$(cat /tmp/il-stdout.$$)
rm -f /tmp/il-stdout.$$ /tmp/il-stderr.$$

if [[ "$rc" == "0" && -z "$stdout_content" ]]; then
  echo "  ✅ SILENT + exit 0: session_start load"
  pass=$((pass + 1))
else
  echo "  ❌ expected silent exit 0 but rc=$rc stdout=<$stdout_content>" >&2
  fail=$((fail + 1))
fi

if [[ -f "$LOG_FILE" ]] && jq -e '.file_path == "/repo/CLAUDE.md" and .load_reason == "session_start" and .session_id == "sess-1"' "$LOG_FILE" >/dev/null 2>&1; then
  echo "  ✅ LOGGED: session_start row has correct file_path/load_reason/session_id"
  pass=$((pass + 1))
else
  echo "  ❌ LOG MISMATCH: expected a row matching session_start payload" >&2
  fail=$((fail + 1))
fi

payload2='{"session_id":"sess-1","cwd":"/repo","hook_event_name":"InstructionsLoaded","file_path":"/repo/skills/foo/CLAUDE.md","memory_type":"Project","load_reason":"nested_traversal","trigger_file_path":"/repo/skills/foo/bar.py"}'
run_hook "$payload2" >/dev/null 2>&1
if [[ "$(wc -l <"$LOG_FILE" | tr -d ' ')" == "2" ]]; then
  echo "  ✅ APPENDS: second load adds a second row, not overwrite"
  pass=$((pass + 1))
else
  echo "  ❌ expected 2 lines in log after 2 loads, got $(wc -l <"$LOG_FILE" | tr -d ' ')" >&2
  fail=$((fail + 1))
fi

if jq -e 'select(.load_reason == "nested_traversal") | .trigger_file_path == "/repo/skills/foo/bar.py"' "$LOG_FILE" >/dev/null 2>&1; then
  echo "  ✅ LOGGED: nested_traversal row carries trigger_file_path"
  pass=$((pass + 1))
else
  echo "  ❌ LOG MISMATCH: nested_traversal row missing trigger_file_path" >&2
  fail=$((fail + 1))
fi

# Malformed payload must not crash the hook or corrupt the log.
run_hook 'not json' >/tmp/il-stdout2.$$ 2>/tmp/il-stderr2.$$
rc=$?
rm -f /tmp/il-stdout2.$$ /tmp/il-stderr2.$$
if [[ "$rc" == "0" ]]; then
  echo "  ✅ EXIT 0: malformed payload doesn't crash the hook"
  pass=$((pass + 1))
else
  echo "  ❌ malformed payload exited $rc, expected 0" >&2
  fail=$((fail + 1))
fi

echo ""
total=$((pass + fail))
echo "=== $pass/$total passed ==="
[[ "$fail" -eq 0 ]] && exit 0 || exit 1
