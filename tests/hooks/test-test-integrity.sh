#!/usr/bin/env bash
# Behavioral tests for hooks/gates/test-integrity.sh. Covers the content-diff
# classifier (assertion removed -> ask, skip marker added -> ask, an added
# always-false conditional/loop wrap around a kept assertion -> ask across
# its if/elif/while and bracket/bare-test spellings), the path narrowing to
# real test-root shapes (not a bare "test"/"spec" substring), and the
# negative controls the adversarial plan review demanded: new-file test
# creation, an edit that only adds an assertion, a non-test path that merely
# contains "test"/"spec" as a substring, and the always-TRUE `[ 0 ]`/
# `[[ false ]]` single-operand tests (must all stay silent). Also proves a
# documented gap stays a documented gap (moving an assertion into an
# uncalled function evades the diff by design, not by accident).
# Run standalone: bash tests/hooks/test-test-integrity.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/hooks/gates/test-integrity.sh"
WORK=$(mktemp -d)
trap 'trash "$WORK" 2>/dev/null || rm -rf "$WORK"' EXIT

pass=0
fail=0

payload_edit() { # payload_edit <file_path> <old_string> <new_string>
  python3 -c 'import json,sys; print(json.dumps({"tool_name":"Edit","tool_input":{"file_path":sys.argv[1],"old_string":sys.argv[2],"new_string":sys.argv[3]}}))' "$1" "$2" "$3"
}

payload_write() { # payload_write <file_path> <content>
  python3 -c 'import json,sys; print(json.dumps({"tool_name":"Write","tool_input":{"file_path":sys.argv[1],"content":sys.argv[2]}}))' "$1" "$2"
}

check() { # check <desc> <ok:0|1>
  if [ "$2" -eq 0 ]; then echo "  ✅ $1"; pass=$((pass + 1))
  else echo "  ❌ $1" >&2; fail=$((fail + 1)); fi
}

is_ask() { echo "$1" | /usr/bin/grep -q '"permissionDecision": "ask"'; }

echo "=== test-integrity gate ==="
cd "$ROOT" || exit 1

TESTFILE="$WORK/tests/hooks/test-sample.sh"
mkdir -p "$(dirname "$TESTFILE")"
cat > "$TESTFILE" <<'EOF'
#!/usr/bin/env bash
check "case one" "$ok1"
check "case two" "$ok2"
EOF

# --- Positive: removing a check() call -> ask ---
out=$(payload_edit "$TESTFILE" 'check "case two" "$ok2"' '' | bash "$GATE" 2>/dev/null)
ok=1; is_ask "$out" && ok=0
check "Edit removing a check() assertion -> ask" "$ok"

# --- Positive: adding a skip marker -> ask ---
out=$(payload_edit "$TESTFILE" 'check "case two" "$ok2"' '# SKIP: check "case two" "$ok2"' | bash "$GATE" 2>/dev/null)
ok=1; is_ask "$out" && ok=0
check "Edit adding a # SKIP marker -> ask" "$ok"

# --- Positive: wrapping a kept assertion in an always-false conditional
# still counts as disabling it, even though the assertion's own line text
# is unchanged (real bypass found by a compliance audit, 2026-08-28) ---
out=$(payload_edit "$TESTFILE" 'check "case two" "$ok2"' 'if false; then
check "case two" "$ok2"
fi' | bash "$GATE" 2>/dev/null)
ok=1; is_ask "$out" && ok=0
check "Edit wrapping an assertion in 'if false; then...fi' -> ask" "$ok"

# --- Positive: the same always-false wrap in its other common spellings
# (elif/while, bracket/bare-test numeric comparisons other than 0/1) --
# a deep-audit fresh-context check (2026-08-28) found these bypassed the
# first version of the fix above; verified live with real bash truthiness
# before adding, not assumed from the regex text. ---
out=$(payload_edit "$TESTFILE" 'check "case two" "$ok2"' 'if [ 1 -eq 2 ]; then
echo x
elif false; then
check "case two" "$ok2"
fi' | bash "$GATE" 2>/dev/null)
ok=1; is_ask "$out" && ok=0
check "Edit wrapping an assertion in 'elif false' -> ask" "$ok"

out=$(payload_edit "$TESTFILE" 'check "case two" "$ok2"' 'while false; do
check "case two" "$ok2"
done' | bash "$GATE" 2>/dev/null)
ok=1; is_ask "$out" && ok=0
check "Edit wrapping an assertion in 'while false; do...done' -> ask" "$ok"

out=$(payload_edit "$TESTFILE" 'check "case two" "$ok2"' 'if [ 1 -eq 2 ]; then
check "case two" "$ok2"
fi' | bash "$GATE" 2>/dev/null)
ok=1; is_ask "$out" && ok=0
check "Edit wrapping an assertion in 'if [ 1 -eq 2 ]' (non-0/1 literals) -> ask" "$ok"

out=$(payload_edit "$TESTFILE" 'check "case two" "$ok2"' 'if test 0 -eq 1; then
check "case two" "$ok2"
fi' | bash "$GATE" 2>/dev/null)
ok=1; is_ask "$out" && ok=0
check "Edit wrapping an assertion in bare 'if test 0 -eq 1' (no brackets) -> ask" "$ok"

# --- Negative: `[ 0 ]` and `[[ false ]]` are single-operand string tests --
# bash evaluates a non-empty string as TRUE regardless of its text, so
# neither actually disables the wrapped assertion. Matching them would be
# a false positive, not a closed gap -- verified live before asserting. ---
out=$(payload_edit "$TESTFILE" 'check "case two" "$ok2"' 'if [ 0 ]; then
check "case two" "$ok2"
fi' | bash "$GATE" 2>/dev/null)
ok=1; is_ask "$out" || ok=0
check "Edit wrapping an assertion in 'if [ 0 ]' (always true) -> noask" "$ok"

out=$(payload_edit "$TESTFILE" 'check "case two" "$ok2"' 'if [[ false ]]; then
check "case two" "$ok2"
fi' | bash "$GATE" 2>/dev/null)
ok=1; is_ask "$out" || ok=0
check "Edit wrapping an assertion in 'if [[ false ]]' (always true) -> noask" "$ok"

# --- Documented gap, not silently unhandled: moving an assertion into a
# function that's never called evades the line-set diff entirely (no
# control-flow/reachability analysis here) -- see the gate's own header. ---
out=$(payload_edit "$TESTFILE" 'check "case two" "$ok2"' 'never_called() {
check "case two" "$ok2"
}' | bash "$GATE" 2>/dev/null)
ok=1; is_ask "$out" || ok=0
check "Edit moving an assertion into an uncalled function -> noask (documented gap)" "$ok"

# --- Negative: only adding a new assertion -> noask ---
out=$(payload_edit "$TESTFILE" 'check "case two" "$ok2"' 'check "case two" "$ok2"
check "case three" "$ok3"' | bash "$GATE" 2>/dev/null)
ok=1; is_ask "$out" || ok=0
check "Edit only adding an assertion -> noask" "$ok"

# --- Negative: new-file test creation -> noask (no old side to weaken) ---
NEWFILE="$WORK/tests/hooks/test-brandnew.sh"
out=$(payload_write "$NEWFILE" 'check "new case" "$ok"' | bash "$GATE" 2>/dev/null)
ok=1; is_ask "$out" || ok=0
check "Write to a brand-new test file -> noask" "$ok"

# --- Negative: non-test path containing "test"/"spec" as a substring -> noask ---
out=$(payload_edit "$WORK/skills/review/test-coverage/SKILL.md" 'assert nothing here' '' | bash "$GATE" 2>/dev/null)
ok=1; is_ask "$out" || ok=0
check "Edit to a path merely containing 'test' as a substring -> noask" "$ok"

echo ""
echo "=== $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
