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

# jest/vitest: removing an expect() from a .spec.ts must ask (rev-2 audit FAIL, 2026-09-05)
SPEC="$WORK/src/foo.spec.ts"; mkdir -p "$(dirname "$SPEC")"
printf 'it("x", () => {\n  expect(a).toBe(1);\n  expect(b).toBe(2);\n});\n' > "$SPEC"
out=$(payload_edit "$SPEC" '  expect(b).toBe(2);' '' | bash "$GATE" 2>/dev/null)
is_ask "$out"; ok=$?
check "Edit removing a jest expect() from .spec.ts -> ask" "$ok"

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

# --- Positive: redefining the check() oracle itself to a no-op silently
# guts every call site without touching a single one of them (deep-audit
# 2026-08-28, confirmed live: call sites stay byte-identical, only the
# helper's own meaning changes -- not a reachability trick, a straight
# diff on the shared assertion helper). ---
out=$(payload_edit "$TESTFILE" 'check() {
  [ "$2" = 0 ] && pass=$((pass + 1)) || fail=$((fail + 1))
}' 'check() {
  pass=$((pass + 1))
}' | bash "$GATE" 2>/dev/null)
ok=1; is_ask "$out" && ok=0
check "Edit redefining the check() oracle to a no-op -> ask" "$ok"

# --- Positive: deleting the final exit-gate line is invisible to a
# call-site diff, but it is the line that turns an accumulated fail count
# into the script's actual exit code -- this repo's own tests (including
# this gate's own) all use this idiom (deep-audit 2026-08-28). ---
out=$(payload_edit "$TESTFILE" '[ "$fail" -eq 0 ] && exit 0 || exit 1' 'echo done' | bash "$GATE" 2>/dev/null)
ok=1; is_ask "$out" && ok=0
check "Edit deleting the [ \$fail -eq 0 ] exit-gate line -> ask" "$ok"

# --- Positive: two textually-identical assertion lines, one removed --
# set-based tracking collapsed both into one entry, so removing one of a
# pair was invisible (deep-audit 2026-08-28; fixed via Counter multisets). ---
out=$(payload_edit "$TESTFILE" 'check "dup" "$okd"
check "dup" "$okd"' 'check "dup" "$okd"' | bash "$GATE" 2>/dev/null)
ok=1; is_ask "$out" && ok=0
check "Edit removing one of two identical assertion lines -> ask" "$ok"

# --- Negative: both identical assertion lines stay -> noask (proves the
# multiset fix does not over-fire on an unrelated same-count edit). ---
out=$(payload_edit "$TESTFILE" 'check "dup" "$okd"
check "dup" "$okd"' 'check "dup" "$okd"
check "dup" "$okd"' | bash "$GATE" 2>/dev/null)
ok=1; is_ask "$out" || ok=0
check "Edit keeping both identical assertion lines -> noask" "$ok"

# --- Positive: relocating an assertion into an inert HEREDOC body leaves
# the line text present but never executed (deep-audit 2026-08-28). ---
out=$(payload_edit "$TESTFILE" 'check "case two" "$ok2"' "cat <<'MARK'
check \"case two\" \"\$ok2\"
MARK" | bash "$GATE" 2>/dev/null)
ok=1; is_ask "$out" && ok=0
check "Edit relocating an assertion into a HEREDOC body -> ask" "$ok"

# --- Positive: relocating an assertion into a ": '...'" colon no-op block
# (bash's inert-multiline-comment idiom) has the identical effect (deep-
# audit 2026-08-28). ---
out=$(payload_edit "$TESTFILE" 'check "case two" "$ok2"' ": '
check \"case two\" \"\$ok2\"
'" | bash "$GATE" 2>/dev/null)
ok=1; is_ask "$out" && ok=0
check "Edit relocating an assertion into a ': ...' no-op block -> ask" "$ok"

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
echo "=== missing lib/_hook_output.py (corrupted/partial plugin install, deep-audit follow-up to #146) ==="
# This gate's embedded python does `from _hook_output import emit_ask`,
# resolved from this gate's sibling lib/ dir. A missing lib module raises
# ModuleNotFoundError -> exit 1, a nonzero non-2 exit that
# hooks/dispatch-pretooluse.py's own contract treats as non-blocking --
# the gated edit proceeds regardless, i.e. this gate fails OPEN. Simulate
# by copying ONLY the .sh + an empty lib/ into an isolated scratch dir
# (never touch the real repo files).
MISSLIB_TI_DIR=$(mktemp -d "${TMPDIR:-/tmp}/kbg-misslib-ti.XXXXXX")
cp "$GATE" "$MISSLIB_TI_DIR/test-integrity.sh"
mkdir -p "$MISSLIB_TI_DIR/lib"
_errf=$(mktemp "${TMPDIR:-/tmp}/kbg-misslib-ti-err.XXXXXX")
# Payload precomputed into a variable, THEN piped via printf (not a live
# python3 producer process) -- the gate exits before reading all of stdin
# (it has no early "$(cat)" stdin-drain like verifier-protect.sh/
# merge-door.sh do), so chaining a live python3 producer directly into it
# triggers a spurious BrokenPipeError/exit-120 on the PRODUCER side that
# `pipefail` then surfaces as this pipeline's own exit code -- a test-harness
# artifact, not a real gate bug (confirmed: $_out already holds the correct
# ask JSON either way).
_payload_ti=$(payload_edit "tests/foo_test.py" 'assert x == 1' 'pass')
_out=$(printf '%s' "$_payload_ti" | bash "$MISSLIB_TI_DIR/test-integrity.sh" 2>"$_errf")
_rc=$?
_ok=1
# Real JSON parse, not a substring grep -- a grep on the literal ask text
# would also pass on a typo'd key Claude Code's own parser would silently
# ignore, falling through to allow on this gate.
if [ "$_rc" -eq 0 ] \
   && echo "$_out" | python3 -c 'import json,sys
d=json.load(sys.stdin)["hookSpecificOutput"]
sys.exit(0 if d["hookEventName"] == "PreToolUse" and d["permissionDecision"] == "ask" and d["permissionDecisionReason"] else 1)' 2>/dev/null \
   && ! /usr/bin/grep -qi "ModuleNotFoundError\|Traceback" "$_errf"; then
  _ok=0
fi
check "missing lib/_hook_output.py -> ask JSON (exit 0), no raw traceback" "$_ok"
rm -f "$_errf"

echo ""
echo "=== $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
