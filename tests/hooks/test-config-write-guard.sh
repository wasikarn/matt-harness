#!/usr/bin/env bash
# Behavioral tests for config-write-guard.sh (#98, deferred backlog from spec #75).
# Run standalone: bash tests/hooks/test-config-write-guard.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GUARD="$ROOT/hooks/gates/config-write-guard.sh"

pass=0
fail=0

payload_write() { # payload_write <file_path>
  python3 -c 'import json,sys; print(json.dumps({"tool_name":"Write","tool_input":{"file_path":sys.argv[1],"content":""}}))' "$1"
}

check() { # check <desc> <ok:0|1>
  if [ "$2" -eq 0 ]; then echo "  ✅ $1"; pass=$((pass + 1))
  else echo "  ❌ $1" >&2; fail=$((fail + 1)); fi
}

echo "=== config-write-guard gate ==="

FIXTURE=$(mktemp -d)
trap 'trash "$FIXTURE" 2>/dev/null || true' EXIT
mkdir -p "$FIXTURE/.claude"

out=$(payload_write "$FIXTURE/.claude/settings.local.json" | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "CREATE .claude/settings.local.json (doesn't exist yet) -> ask" "$ok"

out=$(payload_write "$FIXTURE/.claude/settings.json" | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "CREATE .claude/settings.json (doesn't exist yet) -> ask" "$ok"

echo '{}' > "$FIXTURE/.claude/settings.local.json"
out=$(payload_write "$FIXTURE/.claude/settings.local.json" | bash "$GUARD" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "MODIFY existing .claude/settings.local.json -> exit 0, no output" "$ok"

ln -s "$FIXTURE/.claude/does-not-exist-target" "$FIXTURE/.claude/settings.json"
out=$(payload_write "$FIXTURE/.claude/settings.json" | bash "$GUARD" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "dangling symlink already at settings.json path -> treated as existing, no friction" "$ok"
rm -f "$FIXTURE/.claude/settings.json"

out=$(payload_write "$FIXTURE/.claude/config.json" | bash "$GUARD" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "unrelated .claude/config.json (wrong basename) -> exit 0, no output" "$ok"

out=$(payload_write "$FIXTURE/settings.json" | bash "$GUARD" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "settings.json NOT under a .claude dir -> exit 0, no output" "$ok"

echo ""
total=$((pass + fail))
echo "=== $pass/$total passed ==="
[ "$fail" -eq 0 ] && exit 0 || exit 1
