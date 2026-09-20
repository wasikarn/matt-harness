#!/usr/bin/env bash
# gate:agent:subagent-verdict-check -- Tier 1 of the "auto-apply the attacker
# pattern via hooks?" design note (docs/research/
# nine-agent-gate-architecture-security-audit-2026-09-20.md). Runs every case
# through subagent-verdict-gate.sh (not the .py directly), matching this
# repo's convention that the shell wrapper is part of the contract under test.
# Run standalone: bash tests/hooks/test-subagent-verdict-gate.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SH="$ROOT/hooks/gates/subagent-verdict-gate.sh"

pass=0
fail=0

check() {
  local desc="$1" ok="$2"
  if [ "$ok" -eq 0 ]; then
    echo "  ✅ $desc"
    pass=$((pass + 1))
  else
    echo "  ❌ $desc" >&2
    fail=$((fail + 1))
  fi
}

# payload <msg-json-string> [stop_hook_active]
payload() {
  python3 -c "
import json, sys
msg = sys.argv[1]
d = {'hook_event_name': 'SubagentStop', 'agent_type': 'general-purpose',
     'session_id': 'test-session', 'last_assistant_message': msg}
if len(sys.argv) > 2 and sys.argv[2] == 'active':
    d['stop_hook_active'] = True
print(json.dumps(d))
" "$1" "${2:-}"
}

# run <msg-json-string> [stop_hook_active] -> sets $OUT, $CODE
run() {
  OUT="$(payload "$1" "${2:-}" | bash "$SH" 2>/dev/null)"
  CODE=$?
}

echo "=== subagent-verdict-gate.sh: SubagentStop verdict-shape tests ==="
echo ""

# --- vacuous pass: blocks ---
run '{"pass": true, "findings": [], "scope_ok": true, "unexpected_files": []}'
echo "$OUT" | grep -q '"decision": *"block"' && ok=0 || ok=1
check "vacuous pass (no findings, no checked[]) blocks" "$ok"
[ "$CODE" -eq 0 ]; check "block is still exit 0 (JSON on stdout, not a hook crash)" "$?"

# --- real pass with checked[]: allows ---
run '{"pass": true, "findings": [], "checked": [{"claim": "x", "evidence": "y"}], "scope_ok": true, "unexpected_files": []}'
[ -z "$OUT" ]; check "real pass with checked[] evidence: silent allow" "$?"

# --- self-contradictory: pass true, scope_ok false ---
run '{"pass": true, "findings": [], "checked": [{"claim": "x", "evidence": "y"}], "scope_ok": false, "unexpected_files": []}'
echo "$OUT" | grep -q '"decision": *"block"' && ok=0 || ok=1
check "pass:true + scope_ok:false blocks" "$ok"

# --- self-contradictory: pass true, unexpected_files non-empty ---
run '{"pass": true, "findings": [], "checked": [{"claim": "x", "evidence": "y"}], "scope_ok": true, "unexpected_files": ["extra.py"]}'
echo "$OUT" | grep -q '"decision": *"block"' && ok=0 || ok=1
check "pass:true + non-empty unexpected_files blocks" "$ok"

# --- oversized message: skipped entirely, even a vacuous pass allows ---
run_oversized() {
  local f
  f="$(mktemp)"
  python3 -c "
import json
pad = 'x' * 200_001
msg = '{\"pass\": true, \"findings\": [], \"scope_ok\": true, \"unexpected_files\": []} ' + pad
d = {'hook_event_name': 'SubagentStop', 'agent_type': 'general-purpose',
     'session_id': 'test-session', 'last_assistant_message': msg}
print(json.dumps(d))
" > "$f"
  OUT="$(/bin/bash "$SH" < "$f" 2>/dev/null)"
  CODE=$?
  rm -f "$f"
}
run_oversized
[ -z "$OUT" ]; check "message over 200k chars: skipped, silent allow even on vacuous pass" "$?"

# --- pass:false with real findings: allows ---
run '{"pass": false, "findings": [{"summary": "s", "evidence": "e"}], "checked": [{"claim": "x", "evidence": "y"}], "scope_ok": true, "unexpected_files": []}'
[ -z "$OUT" ]; check "pass:false with real findings: silent allow" "$?"

# --- NEEDS-DECISION always allows, even with a decoy JSON blob ---
run 'NEEDS-DECISION which schema should I use? (example: {"pass": true})'
[ -z "$OUT" ]; check "NEEDS-DECISION text: silent allow" "$?"

# --- ambiguous: two distinct pass-bearing objects ---
run 'Draft: {"pass": true, "findings": []} then final: {"pass": false, "findings": [{"summary":"s","evidence":"e"}]}'
[ -z "$OUT" ]; check "two distinct pass objects: allow (ambiguous, noted on stderr only)" "$?"

# --- ordinary prose, no verdict shape: allows ---
run 'I explored the codebase and found three files matching the pattern.'
[ -z "$OUT" ]; check "ordinary non-verdict prose: silent allow" "$?"

# --- stop_hook_active: already re-prompted once, never block again ---
run '{"pass": true, "findings": [], "scope_ok": true, "unexpected_files": []}' active
[ -z "$OUT" ]; check "stop_hook_active:true: never blocks a second time" "$?"

# --- fail-open on missing python3 ---
run_no_python3() {
  # Write the payload to a file first, not a pipe -- with `set -o pipefail`,
  # the shell script exiting before python3 finishes writing raises a
  # BrokenPipeError in the payload generator, which then (wrongly) becomes
  # this test's observed exit code instead of subagent-verdict-gate.sh's own.
  local f
  f="$(mktemp)"
  payload '{"pass": true, "findings": [], "scope_ok": true, "unexpected_files": []}' > "$f"
  OUT="$(PATH="/nonexistent" /bin/bash "$SH" < "$f" 2>/dev/null)"
  CODE=$?
  rm -f "$f"
}
run_no_python3
[ "$CODE" -eq 0 ] && [ -z "$OUT" ]; check "missing python3: exit 0, no block JSON (fail-open)" "$?"

# --- fail-open when the sibling .py is missing (would otherwise let
# python3's own "no such file" exit code, commonly 2, be misread by Claude
# Code as an explicit SubagentStop block) ---
run_missing_sibling() {
  local f tmp_sh
  f="$(mktemp)"
  payload '{"pass": true, "findings": [], "scope_ok": true, "unexpected_files": []}' > "$f"
  tmp_sh="$(mktemp)"
  sed "s#subagent-verdict-gate.py#does-not-exist.py#" "$SH" > "$tmp_sh"
  OUT="$(/bin/bash "$tmp_sh" < "$f" 2>/dev/null)"
  CODE=$?
  rm -f "$f" "$tmp_sh"
}
run_missing_sibling
[ "$CODE" -eq 0 ] && [ -z "$OUT" ]; check "missing sibling .py: exit 0, no block JSON (fail-open)" "$?"

echo ""
echo "=== Results: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
