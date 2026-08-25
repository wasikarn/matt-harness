#!/usr/bin/env bash
# Behavioral tests for hooks/dispatch-single.sh (T12 #91) -- the profile-tier
# and kill-switch filter every non-PreToolUse hook now routes through.
# PreToolUse gates never use this wrapper (see dispatch-pretooluse.sh/.py and
# their own test file) -- there is no tiering concept for gates at all.
# Run standalone: bash tests/hooks/test-dispatch-single.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DISPATCH="$ROOT/hooks/dispatch-single.sh"

pass=0
fail=0

TMP=$(mktemp -d "${TMPDIR:-/tmp}/dispatch-single.XXXXXX")
trap 'trash "$TMP" 2>/dev/null || true' EXIT

REAL_SCRIPT="$TMP/real.sh"
cat > "$REAL_SCRIPT" <<'EOF'
#!/usr/bin/env bash
echo "ran: $*"
exit 0
EOF
chmod +x "$REAL_SCRIPT"

check() { # check <desc> <ok:0|1>
  if [ "$2" -eq 0 ]; then echo "  ✅ $1"; pass=$((pass + 1))
  else echo "  ❌ $1" >&2; fail=$((fail + 1)); fi
}

echo "=== default profile (unset MH_HOOK_PROFILE) reproduces today's exact behavior ==="
out=$(env -u MH_HOOK_PROFILE -u MH_DISABLED_HOOKS bash "$DISPATCH" "test:strict-hook" "strict" "$REAL_SCRIPT"); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ "$out" = "ran: " ] && ok=0
check "unset profile defaults to strict -- a strict-tier hook still fires (no prior install is silently made quieter)" "$ok"

echo "=== profile tiering ==="
out=$(env MH_HOOK_PROFILE=minimal bash "$DISPATCH" "test:standard-hook" "standard" "$REAL_SCRIPT" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "minimal profile filters out a standard-tier hook (exit 0, no run)" "$ok"

out=$(env MH_HOOK_PROFILE=minimal bash "$DISPATCH" "test:strict-hook" "strict" "$REAL_SCRIPT" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "minimal profile filters out a strict-tier hook (exit 0, no run)" "$ok"

out=$(env MH_HOOK_PROFILE=minimal bash "$DISPATCH" "test:minimal-hook" "minimal" "$REAL_SCRIPT"); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ "$out" = "ran: " ] && ok=0
check "minimal profile still runs a minimal-tier hook" "$ok"

out=$(env MH_HOOK_PROFILE=standard bash "$DISPATCH" "test:standard-hook" "standard" "$REAL_SCRIPT"); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ "$out" = "ran: " ] && ok=0
check "standard profile runs a standard-tier hook" "$ok"

out=$(env MH_HOOK_PROFILE=standard bash "$DISPATCH" "test:strict-hook" "strict" "$REAL_SCRIPT" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "standard profile filters out a strict-tier hook" "$ok"

out=$(env MH_HOOK_PROFILE=strict bash "$DISPATCH" "test:strict-hook" "strict" "$REAL_SCRIPT"); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ "$out" = "ran: " ] && ok=0
check "strict profile runs a strict-tier hook" "$ok"

echo "=== kill switch ==="
out=$(env -u MH_HOOK_PROFILE MH_DISABLED_HOOKS="test:minimal-hook" bash "$DISPATCH" "test:minimal-hook" "minimal" "$REAL_SCRIPT" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "kill switch disables even a minimal-tier hook by id (non-PreToolUse hooks have no immunity)" "$ok"

out=$(env -u MH_HOOK_PROFILE MH_DISABLED_HOOKS="some:other,test:minimal-hook,another:one" bash "$DISPATCH" "test:minimal-hook" "minimal" "$REAL_SCRIPT" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "kill switch matches an id inside a comma-separated list, not just a single-id list" "$ok"

out=$(env -u MH_HOOK_PROFILE MH_DISABLED_HOOKS="test:other-hook" bash "$DISPATCH" "test:minimal-hook" "minimal" "$REAL_SCRIPT"); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ "$out" = "ran: " ] && ok=0
check "kill switch does not false-positive on an unrelated id in the list" "$ok"

echo "=== argument pass-through ==="
out=$(env MH_HOOK_PROFILE=strict bash "$DISPATCH" "test:with-args" "minimal" "$REAL_SCRIPT" "extra" "args"); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ "$out" = "ran: extra args" ] && ok=0
check "extra args after the real script path are forwarded to it" "$ok"

echo
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
