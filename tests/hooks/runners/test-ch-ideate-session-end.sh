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

# 6. Dynamic: convergence hook correctly parses a JSONL transcript with a
# nested ideate Skill call and appends a record.
JSONL_CONV="$FIXTURE/jsonl-conv-transcript.jsonl"
cat > "$JSONL_CONV" <<'EOF'
{"type":"user","message":{"role":"user","content":"/ideate how to refactor auth"},"timestamp":"2026-06-18T10:00:00Z","sessionId":"jsonl-conv"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Skill","input":{"skill":"ideate"}}]},"timestamp":"2026-06-18T10:00:01Z","sessionId":"jsonl-conv"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"some ideas"}]},"timestamp":"2026-06-18T10:01:00Z","sessionId":"jsonl-conv"}
EOF
SE_JSONL='{"hook_event_name":"SessionEnd","session_id":"jsonl-conv","transcript_path":"'$JSONL_CONV'"}'
HOME="$FIXTURE" KBG_IDEATE_OLLAMA_TIMEOUT=1 \
  check_task "session/ideate-convergence-capture.sh" 0 "" "appends record for JSONL ideate call" "$SE_JSONL"
# The hook forks the capture to a `nohup` background child and returns in
# <50ms, so the record lands after the hook exits. Poll for it (also drains
# the worker so it cannot leak a late write into test #8's isolated state).
_record_ok=0
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  if [ -s "$FIXTURE/.claude/state/ideate-embeddings.jsonl" ] \
      && /usr/bin/grep -qF '"session_id":"jsonl-conv"' "$FIXTURE/.claude/state/ideate-embeddings.jsonl"; then
    _record_ok=1; break
  fi
  sleep 0.3
done
if [ "$_record_ok" = "1" ]; then
  PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "convergence-capture" "record present in isolated state"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-22s %s\n' "convergence-capture" "record missing in isolated state"
fi

# 7. Dynamic: budget hook correctly counts an ideate call in a JSONL transcript.
JSONL_BUD="$FIXTURE/jsonl-bud-transcript.jsonl"
cat > "$JSONL_BUD" <<'EOF'
{"type":"user","message":{"role":"user","content":"/ideate how to refactor auth"},"timestamp":"2026-06-18T10:00:00Z","sessionId":"jsonl-bud"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Skill","input":{"skill":"kbg:ideate"}}]},"timestamp":"2026-06-18T10:00:01Z","sessionId":"jsonl-bud"}
EOF
SE_BUD='{"hook_event_name":"SessionEnd","session_id":"jsonl-bud","transcript_path":"'$JSONL_BUD'"}'
HOME="$FIXTURE" check_task "session/ideate-budget-capture.sh" 0 "" "appends usage for JSONL kbg:ideate call" "$SE_BUD"
if [ -s "$FIXTURE/.claude/state/ideate-usage.jsonl" ] \
    && /usr/bin/grep -qF '"session_id":"jsonl-bud"' "$FIXTURE/.claude/state/ideate-usage.jsonl"; then
  PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "budget-capture" "usage row present in isolated state"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-22s %s\n' "budget-capture" "usage row missing in isolated state"
fi

# 8. Dynamic: convergence hook exits 0 and leaves state untouched when there
# are no ideate calls in a JSONL transcript.
JSONL_EMPTY="$FIXTURE/jsonl-empty-transcript.jsonl"
cat > "$JSONL_EMPTY" <<'EOF'
{"type":"user","message":{"role":"user","content":"hello"},"timestamp":"2026-06-18T10:00:00Z","sessionId":"jsonl-empty"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"hi"}]},"timestamp":"2026-06-18T10:00:01Z","sessionId":"jsonl-empty"}
EOF
SE_EMPTY='{"hook_event_name":"SessionEnd","session_id":"jsonl-empty","transcript_path":"'$JSONL_EMPTY'"}'
rm -f "$FIXTURE/.claude/state/ideate-embeddings.jsonl"
HOME="$FIXTURE" check_task "session/ideate-convergence-capture.sh" 0 "" "exits 0 with no ideate calls" "$SE_EMPTY"
if [ -f "$FIXTURE/.claude/state/ideate-embeddings.jsonl" ]; then
  FAIL=$((FAIL+1)); printf '  ❌ %-22s %s\n' "convergence-capture" "wrote state when no ideate calls"
else
  PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "convergence-capture" "no state written when no ideate calls"
fi

report
