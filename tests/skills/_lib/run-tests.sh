#!/usr/bin/env bash
# run-tests.sh — deterministic guards for skills/_lib/err.sh.
#
# Convention mirrors tests/acli + tests/memory-lint:
# each skill/lib owns its tests; fixtures live in-repo for reproducibility.
#
# Exit 0 = all pass, 1 = at least one failure.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ERR="$HERE/../../../skills/_lib/err.sh"

pass=0
fail=0
fail_msgs=()

check_eq() {  # <label> <actual> <expected>
    if [ "$2" = "$3" ]; then
        echo "  PASS: $1"
        pass=$((pass + 1))
    else
        echo "  FAIL: $1"
        fail_msgs+=("$1 — expected '$3', got '$2'")
        fail=$((fail + 1))
    fi
}

check_contains() {  # <label> <output> <needle>
    if printf '%s' "$2" | /usr/bin/grep -qF -- "$3"; then
        echo "  PASS: $1"
        pass=$((pass + 1))
    else
        echo "  FAIL: $1"
        fail_msgs+=("$1 — expected to find: $3")
        fail=$((fail + 1))
    fi
}

# Source the lib so helper functions are available in this shell.
# shellcheck source=../../../skills/_lib/err.sh
. "$ERR"

# ── err_die ───────────────────────────────────────────────────────────
echo "── err_die: exits 1 with ERROR prefix ──"
out=$(bash -c '. '"$ERR"'; err_die "boom"' 2>&1) || code=$?
check_eq "exit code is 1" "${code:-0}" "1"
check_contains "stderr has ERROR prefix" "$out" "ERROR: boom"
unset code

echo "── err_die: custom exit code ──"
out=$(bash -c '. '"$ERR"'; err_die "nope" 7' 2>&1) || code=$?
check_eq "exit code is custom" "${code:-0}" "7"
check_contains "stderr preserved" "$out" "ERROR: nope"
unset code

# ── err_warn ───────────────────────────────────────────────────────────
echo "── err_warn: does not exit, prints WARN prefix ──"
out=$(bash -c '. '"$ERR"'; err_warn "careful"; echo done' 2>&1)
check_contains "stdout continues" "$out" "done"
check_contains "stderr has WARN prefix" "$out" "WARN: careful"

# ── err_usage ──────────────────────────────────────────────────────────
echo "── err_usage: exits 2 with usage prefix ──"
out=$(bash -c '. '"$ERR"'; err_usage "foo [--bar]"' 2>&1) || code=$?
check_eq "exit code is 2" "${code:-0}" "2"
check_contains "stderr has usage prefix" "$out" "usage: foo [--bar]"
unset code

# ── require_cmd ────────────────────────────────────────────────────────
echo "── require_cmd: fails on missing command ──"
out=$(bash -c '. '"$ERR"'; require_cmd definitely-not-a-real-command' 2>&1) || code=$?
check_eq "exit code is 1" "${code:-0}" "1"
check_contains "stderr names missing command" "$out" "required command not found"
unset code

echo "── require_cmd: succeeds on present command ──"
out=$(bash -c '. '"$ERR"'; require_cmd bash; echo ok') 2>&1
check_eq "exit code is 0" "$?" "0"
check_contains "stdout continues" "$out" "ok"

# ── temp_register / temp_cleanup ────────────────────────────────────────
echo "── temp_register: removes registered temp file on EXIT ──"
tmpdir=$(mktemp -d)
file="$tmpdir/err-test-$$"
bash -c '. '"$ERR"'; tmp="'"$file"'"; touch "$tmp"; temp_register "$tmp"; [ -f "$tmp" ] || exit 9'
code=$?
check_eq "script exited cleanly" "$code" "0"
check_eq "temp file removed after exit" "$(test -f "$file" && echo present || echo gone)" "gone"
rm -rf "$tmpdir"
unset code

echo ""
if [ "$fail" -eq 0 ]; then
    echo "All $pass tests passed."
    exit 0
else
    echo "$pass passed, $fail failed:"
    for msg in "${fail_msgs[@]}"; do
        echo "  - $msg"
    done
    exit 1
fi
