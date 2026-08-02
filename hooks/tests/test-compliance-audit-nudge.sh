#!/usr/bin/env bash
# compliance-audit-nudge unit tests: simulates PostToolUse/Bash JSON payloads
# (with a real fixture transcript file for the ExitPlanMode-detection cases)
# and asserts stdout output (JSON with additionalContext) vs silence (nudge
# skipped). The hook never blocks, so all tests expect exit 0.
# Run standalone: bash hooks/tests/test-compliance-audit-nudge.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/hooks/advisory/compliance-audit-nudge.sh"
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

pass=0
fail=0

# Build a PostToolUse/Bash payload for a given command + transcript path.
bash_payload() {
  local cmd="$1" transcript="$2"
  python3 -c '
import sys, json
print(json.dumps({
    "tool_name": "Bash",
    "tool_input": {"command": sys.argv[1]},
    "transcript_path": sys.argv[2],
}, ensure_ascii=False))
' "$cmd" "$transcript"
}

# Fixture: a transcript with a real ExitPlanMode tool_use + non-empty plan,
# plus a deferred_tools_delta attachment entry that ALSO mentions
# "ExitPlanMode" by name -- the exact false-positive shape a naive grep
# alone would misread as a real approval.
WITH_PLAN="$WORKDIR/with-plan.jsonl"
cat > "$WITH_PLAN" <<'EOF'
{"type":"user","message":{"role":"user","content":"do the thing"}}
{"type":"attachment","attachment":{"type":"deferred_tools_delta","addedNames":["EnterPlanMode","ExitPlanMode"]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"ExitPlanMode","input":{"plan":"# A real plan\nDo the thing.","planFilePath":"/tmp/fake-plan.md"}}]}}
{"type":"user","message":{"role":"user","content":"looks good"}}
EOF

# Fixture: only the attachment noise, no real ExitPlanMode tool_use/plan.
NO_PLAN="$WORKDIR/no-plan.jsonl"
cat > "$NO_PLAN" <<'EOF'
{"type":"user","message":{"role":"user","content":"do the thing"}}
{"type":"attachment","attachment":{"type":"deferred_tools_delta","addedNames":["EnterPlanMode","ExitPlanMode"]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"done, no plan mode used"}]}}
EOF

echo "=== compliance-audit-nudge hook (PostToolUse:Bash) ==="
echo ""
echo "--- commit after a real plan approval (must emit nudge JSON, exit 0) ---"
out=$(bash_payload 'git commit -m "test commit"' "$WITH_PLAN" | bash "$HOOK" 2>/dev/null)
rc=$?
if [[ "$rc" == "0" ]] \
   && printf '%s' "$out" | /usr/bin/grep -q '"additionalContext"' \
   && printf '%s' "$out" | /usr/bin/grep -q "kbg:compliance-audit" \
   && printf '%s' "$out" | /usr/bin/grep -q '"hookEventName": "PostToolUse"'; then
  echo "  ✅ NUDGE: commit after plan approval emits valid additionalContext JSON"
  pass=$((pass + 1))
else
  echo "  ❌ NUDGE EXPECTED but rc=$rc stdout=<$(printf '%s' "$out" | head -c 200)>" >&2
  fail=$((fail + 1))
fi

# Output must be valid JSON, not just grep-matched text.
if printf '%s' "$out" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
  echo "  ✅ VALID JSON: nudge output parses cleanly"
  pass=$((pass + 1))
else
  echo "  ❌ INVALID JSON: <$(printf '%s' "$out" | head -c 200)>" >&2
  fail=$((fail + 1))
fi

# Regression test for plan-reviewer's Critical finding: compliance-audit is
# disable-model-invocation:true, so the nudge must tell the user to run it
# themselves, never instruct the model to dispatch/invoke it.
if printf '%s' "$out" | /usr/bin/grep -q "tell the user they can run" \
   && printf '%s' "$out" | /usr/bin/grep -q "do not dispatch or invoke it yourself"; then
  echo "  ✅ WORDING: nudge tells the model to relay, not to dispatch/invoke"
  pass=$((pass + 1))
else
  echo "  ❌ WORDING: nudge must instruct relay-to-user, not self-dispatch: <$(printf '%s' "$out" | head -c 300)>" >&2
  fail=$((fail + 1))
fi

echo ""
echo "--- silent cases (must stay silent, exit 0) ---"

silent_case() {
  local desc="$1" payload="$2"
  local out rc
  out=$(printf '%s' "$payload" | bash "$HOOK" 2>/dev/null)
  rc=$?
  if [[ "$rc" == "0" && -z "$out" ]]; then
    echo "  ✅ SILENT: $desc"
    pass=$((pass + 1))
  else
    echo "  ❌ SILENT EXPECTED but rc=$rc stdout=<$(printf '%s' "$out" | head -c 80)>: $desc" >&2
    fail=$((fail + 1))
  fi
}

silent_case "non-commit Bash command (bogus transcript_path, must not matter)" \
  "$(bash_payload 'ls -la' '/nonexistent/path.jsonl')"
silent_case "git commit-graph (must not false-match commit)" \
  "$(bash_payload 'git commit-graph write' "$WITH_PLAN")"
silent_case "git commit-tree (must not false-match commit)" \
  "$(bash_payload 'git commit-tree HEAD^{tree}' "$WITH_PLAN")"
silent_case "commit, but transcript has no real ExitPlanMode entry" \
  "$(bash_payload 'git commit -m "no plan"' "$NO_PLAN")"
silent_case "commit, but transcript_path missing/nonexistent" \
  "$(bash_payload 'git commit -m "no transcript"' '/nonexistent/path.jsonl')"
silent_case "malformed JSON" \
  'not json at all'
silent_case "empty stdin" \
  ""

echo ""
total=$((pass + fail))
echo "=== $pass/$total passed ==="
[[ "$fail" -eq 0 ]] && exit 0 || exit 1
