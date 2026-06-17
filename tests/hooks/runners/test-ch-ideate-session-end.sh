#!/usr/bin/bash
# shellcheck disable=SC1091
source "$(dirname "$0")/test-critical-hooks-lib.sh"
# test-ch-ideate-session-end — verifies the two ideate SessionEnd advisory hooks
# stay within the Claude CLI hook budget and never block on Ollama/qmd.

echo
echo "--- ideate SessionEnd hook budget ---"

# 1. Static: timeout env var is wired into the Ollama call.
if /usr/bin/grep -qF 'KBG_IDEATE_OLLAMA_TIMEOUT' "$HOOKS/session/ideate-convergence-capture.sh"; then
  PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "convergence-capture" "KBG_IDEATE_OLLAMA_TIMEOUT wired"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-22s %s\n' "convergence-capture" "missing OLLAMA_TIMEOUT wiring"
fi

# 2. Static: memory reindex is forked to background.
if /usr/bin/grep -qE 'nohup.*index' "$HOOKS/session/ideate-memory-capture.sh"; then
  PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "memory-capture" "qmd index runs async"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-22s %s\n' "memory-capture" "qmd index still synchronous"
fi

# 3. Static: hooks.json declares an explicit SessionEnd timeout for both hooks.
for _h in ideate-convergence-capture ideate-memory-capture; do
  if python3 -c "import json,sys; d=json.load(open('$HOOKS/hooks.json')); print(any('$_h' in h.get('command','') and 'timeout' in h for g in d['hooks']['SessionEnd'] for h in g.get('hooks',[])))" | /usr/bin/grep -qF "True"; then
    PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "$_h" "hooks.json timeout declared"
  else
    FAIL=$((FAIL+1)); printf '  ❌ %-22s %s\n' "$_h" "hooks.json timeout missing"
  fi
done

# 4. Dynamic: convergence hook exits 0 on an empty SessionEnd envelope (no ideate calls).
SE_EVENT='{"hook_event_name":"SessionEnd","session_id":"se-test","transcript_path":"/dev/null"}'
check_task "session/ideate-convergence-capture.sh" 0 "" "exits 0 with empty envelope" "$SE_EVENT"

# 5. Dynamic: memory hook exits 0 on an empty SessionEnd envelope.
check_task "session/ideate-memory-capture.sh" 0 "" "exits 0 with empty envelope" "$SE_EVENT"

report
