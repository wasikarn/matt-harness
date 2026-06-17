#!/bin/bash
HOOKS="$(cd "$(dirname "$0")/../../../hooks" && pwd)"
HOOK="$HOOKS/advisory/orchestrator-nudge.sh"
test_prompt() {
  local label="$1" prompt="$2" expect="$3"
  local out
  out=$(printf '{"prompt":%s}\n' "$(printf '%s' "$prompt" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" | bash "$HOOK" 2>&1)
  local fired=""
  if echo "$out" | grep -q "Heuristic match"; then
    fired=$(echo "$out" | grep -oE "\(([a-z-]+)\)" | head -1 | tr -d '()')
  fi
  if [ "$fired" = "$expect" ]; then
    printf '  ✅ %-60s fired=%s\n' "$label" "${fired:-<none>}"
  else
    printf '  ❌ %-60s expected=%s got=%s\n   out: %s\n' "$label" "$expect" "${fired:-<none>}" "$out"
  fi
}

echo "=== existing routes (regression) ==="
test_prompt "iteration-over-set still fires" "refactor all the agents" "iteration-over-set"
test_prompt "comprehensive-breadth still fires" "comprehensive review of the codebase" "comprehensive-breadth"
test_prompt "no-match stays silent" "hello world" ""

echo
echo "=== path-overlap NEW (≥2 contexts) ==="
test_prompt "Execution + Quality paths" "fix the bug in app/api/users.py and add a test in tests/test_users.py" "path-overlap"
test_prompt "Execution + Emergency paths" "fix app/api/users.py and update runbooks/incident-2026-06-04.md" "path-overlap"
test_prompt "Quality + Communication paths" "review tests/test_users.py and update docs/api.md" "path-overlap"
test_prompt "Implementation + Communication paths" "fix src/api/users.py and update docs/api.md" "path-overlap"

echo
echo "=== path-overlap NEGATIVE (should stay silent or be other) ==="
test_prompt "single-context paths (Execution only)" "fix the bug in app/api/users.py" ""
test_prompt "single-context paths (Quality only)" "review tests/test_users.py" ""
test_prompt "no paths at all" "refactor all the agents" "iteration-over-set"
test_prompt "Thai prompt with no paths" "ช่วยแก้บัคหน่อย" ""

echo
echo "=== bypass ==="
out=$(printf '{"prompt":"fix the bug in app/api/users.py and add a test in tests/test_users.py"}\n' | CLAUDE_DISABLED_HOOKS=orchestrator-nudge bash "$HOOK" 2>&1)
if [ -z "$out" ]; then
  echo "  ✅ bypass env disables hook"
else
  echo "  ❌ bypass env did not disable: $out"
fi
