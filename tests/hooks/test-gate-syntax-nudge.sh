#!/usr/bin/env bash
# gate-syntax-nudge unit tests: simulates PostToolUse/Edit|Write JSON payloads
# against real fixture .sh files (clean and syntactically broken) placed at
# both in-scope (hooks/gates, hooks/advisory) and out-of-scope paths, and
# asserts stdout output (JSON with additionalContext) vs silence. The hook
# never blocks, so all tests expect exit 0.
# Run standalone: bash tests/hooks/test-gate-syntax-nudge.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/hooks/advisory/gate-syntax-nudge.sh"
WORKDIR=$(mktemp -d)
trap 'trash "$WORKDIR" 2>/dev/null || true' EXIT

pass=0
fail=0

mkdir -p "$WORKDIR/hooks/gates" "$WORKDIR/hooks/advisory" "$WORKDIR/hooks/session" "$WORKDIR/other"

printf '#!/usr/bin/env bash\necho hello\n' > "$WORKDIR/hooks/gates/clean-gate.sh"
printf '#!/usr/bin/env bash\necho hello\n' > "$WORKDIR/hooks/advisory/clean-advisory.sh"
printf '#!/usr/bin/env bash\necho hello\n' > "$WORKDIR/hooks/session/clean-session.sh"
printf '#!/usr/bin/env bash\necho hello\n' > "$WORKDIR/other/clean-other.sh"

# Broken via an unclosed single-quote inside an embedded python3 -c block --
# the exact real-world failure mode this hook exists to catch (2026-09-01
# incident, verifier-protect.sh).
printf '#!/usr/bin/env bash\npython3 -c '"'"'a = 1\nif True:\n' > "$WORKDIR/hooks/gates/broken-gate.sh"
printf '#!/usr/bin/env bash\npython3 -c '"'"'a = 1\nif True:\n' > "$WORKDIR/hooks/advisory/broken-advisory.sh"
printf '#!/usr/bin/env bash\npython3 -c '"'"'a = 1\nif True:\n' > "$WORKDIR/hooks/session/broken-session.sh"

# Build a PostToolUse/Edit payload for a given file_path.
edit_payload() {
  local fp="$1"
  python3 -c '
import sys, json
print(json.dumps({
    "tool_name": "Edit",
    "tool_input": {"file_path": sys.argv[1]},
}, ensure_ascii=False))
' "$fp"
}

echo "=== gate-syntax-nudge hook (PostToolUse:Edit|Write) ==="
echo ""
echo "--- warn cases (must emit nudge JSON, exit 0) ---"

warn_case() {
  local desc="$1" fp="$2"
  local out rc
  out=$(edit_payload "$fp" | bash "$HOOK" 2>/dev/null)
  rc=$?
  if [[ "$rc" == "0" ]] \
     && printf '%s' "$out" | /usr/bin/grep -q '"additionalContext"' \
     && printf '%s' "$out" | /usr/bin/grep -q "mh:gate-syntax-nudge" \
     && printf '%s' "$out" | /usr/bin/grep -q '"hookEventName": "PostToolUse"'; then
    echo "  ✅ NUDGE: $desc"
    pass=$((pass + 1))
  else
    echo "  ❌ NUDGE EXPECTED but rc=$rc stdout=<$(printf '%s' "$out" | head -c 200)>: $desc" >&2
    fail=$((fail + 1))
  fi
  if printf '%s' "$out" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
    echo "  ✅ VALID JSON: $desc"
    pass=$((pass + 1))
  else
    echo "  ❌ INVALID JSON: <$(printf '%s' "$out" | head -c 200)>: $desc" >&2
    fail=$((fail + 1))
  fi
}

warn_case "broken hooks/gates/*.sh file" "$WORKDIR/hooks/gates/broken-gate.sh"
warn_case "broken hooks/advisory/*.sh file" "$WORKDIR/hooks/advisory/broken-advisory.sh"

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

silent_case "clean hooks/gates/*.sh file" "$(edit_payload "$WORKDIR/hooks/gates/clean-gate.sh")"
silent_case "clean hooks/advisory/*.sh file" "$(edit_payload "$WORKDIR/hooks/advisory/clean-advisory.sh")"
silent_case "broken file OUTSIDE hooks/gates or hooks/advisory (hooks/session, in-scope-adjacent but not covered)" \
  "$(edit_payload "$WORKDIR/hooks/session/broken-session.sh")"
silent_case "broken file at an unrelated path" \
  "$(edit_payload "$WORKDIR/other/clean-other.sh")"
silent_case "file_path missing from payload" \
  '{"tool_name":"Edit","tool_input":{}}'
silent_case "file_path points at a nonexistent file" \
  "$(edit_payload "$WORKDIR/hooks/gates/does-not-exist.sh")"
silent_case "decoy file_path inside tool_response must not win over the real tool_input.file_path" \
  '{"tool_name":"Edit","tool_input":{"file_path":"'"$WORKDIR"'/hooks/gates/clean-gate.sh"},"tool_response":{"file_path":"'"$WORKDIR"'/hooks/gates/broken-gate.sh"}}'
silent_case "malformed JSON" \
  'not json at all'
silent_case "empty stdin" \
  ""

echo ""
total=$((pass + fail))
echo "=== $pass/$total passed ==="
[[ "$fail" -eq 0 ]] && exit 0 || exit 1
