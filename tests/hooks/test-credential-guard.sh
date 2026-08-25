#!/usr/bin/env bash
# Behavioral tests for hooks/gates/credential-guard.sh (#96). Covers the
# core deny cases, the realpath/symlink-indirection bypass this gate exists
# to close, and the false-positive cases a naive substring match would trip.
# Run standalone: bash tests/hooks/test-credential-guard.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GUARD="$ROOT/hooks/gates/credential-guard.sh"
WORK=$(mktemp -d)
trap 'trash "$WORK" 2>/dev/null || rm -rf "$WORK"' EXIT

pass=0
fail=0

payload_read() { # payload_read <file_path>
  python3 -c 'import json,sys; print(json.dumps({"tool_name":"Read","tool_input":{"file_path":sys.argv[1]}}))' "$1"
}

payload_grep() { # payload_grep <path>
  python3 -c 'import json,sys; print(json.dumps({"tool_name":"Grep","tool_input":{"pattern":"x","path":sys.argv[1]}}))' "$1"
}

check() { # check <desc> <ok:0|1>
  if [ "$2" -eq 0 ]; then echo "  ✅ $1"; pass=$((pass + 1))
  else echo "  ❌ $1" >&2; fail=$((fail + 1)); fi
}

echo "=== credential-guard gate ==="
cd "$ROOT" || exit 1

# --- Direct deny cases ---
out=$(payload_read "$WORK/.env" | bash "$GUARD" 2>&1 >/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && echo "$out" | /usr/bin/grep -q "BLOCKED" && ok=0
check "Read .env -> denied" "$ok"

touch "$WORK/id_rsa"
out=$(payload_read "$WORK/id_rsa" | bash "$GUARD" 2>&1 >/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "Read id_rsa -> denied" "$ok"

out=$(payload_read "$WORK/creds.pem" | bash "$GUARD" 2>&1 >/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "Read *.pem -> denied" "$ok"

out=$(payload_grep "$WORK/.netrc" | bash "$GUARD" 2>&1 >/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "Grep path=.netrc -> denied" "$ok"

out=$(payload_read "$WORK/my-service-account.json" | bash "$GUARD" 2>&1 >/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "Read *service-account*.json -> denied" "$ok"

# --- Symlink-indirection bypass (the reason this gate resolves realpath) ---
touch "$WORK/real_id_rsa_target"
mv "$WORK/real_id_rsa_target" "$WORK/id_rsa" 2>/dev/null || true
ln -sf "$WORK/id_rsa" "$WORK/notes.txt"
out=$(payload_read "$WORK/notes.txt" | bash "$GUARD" 2>&1 >/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "Read notes.txt symlinked to id_rsa -> denied (realpath resolution)" "$ok"

# --- False positives: must NOT be blocked ---
touch "$WORK/.env.example"
out=$(payload_read "$WORK/.env.example" | bash "$GUARD" 2>&1 >/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && ok=0
check "Read .env.example -> allowed" "$ok"

touch "$WORK/service-account-docs.md"
out=$(payload_read "$WORK/service-account-docs.md" | bash "$GUARD" 2>&1 >/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && ok=0
check "Read service-account-docs.md -> allowed" "$ok"

out=$(payload_read "$ROOT/README.md" | bash "$GUARD" 2>&1 >/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && ok=0
check "Read unrelated repo file -> allowed" "$ok"

# --- Directory target (Grep with no specific file) is a known gap, not a false deny ---
out=$(payload_grep "$WORK" | bash "$GUARD" 2>&1 >/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && ok=0
check "Grep path=directory -> allowed (out of scope, see header)" "$ok"

echo ""
echo "=== $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
