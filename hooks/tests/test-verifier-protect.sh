#!/usr/bin/env bash
# Behavioral tests for verifier-protect.sh (always-on gate — no opt-in condition,
# unlike worktree-guard.py — fires on every Bash/Write/Edit call in every repo running
# this plugin). Had zero automated coverage before 2026-08-04: this file was added the
# same day as the round-3 port of worktree-guard.py's heredoc/ANSI-C/newline/$VAR/~
# fixes into this gate's own embedded generator, specifically to close that gap.
# Run standalone: bash hooks/tests/test-verifier-protect.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GUARD="$ROOT/hooks/gates/verifier-protect.sh"

pass=0
fail=0

payload_bash() { # payload_bash <command>
  python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$1"
}

payload_write() { # payload_write <file_path> [content]
  python3 -c 'import json,sys; print(json.dumps({"tool_name":"Write","tool_input":{"file_path":sys.argv[1],"content":sys.argv[2] if len(sys.argv)>2 else ""}}))' "$@"
}

check() { # check <desc> <ok:0|1>
  if [ "$2" -eq 0 ]; then echo "  ✅ $1"; pass=$((pass + 1))
  else echo "  ❌ $1" >&2; fail=$((fail + 1)); fi
}

echo "=== verifier-protect gate ==="

cd "$ROOT" || exit 1

# Baseline sanity (pre-existing behavior, not touched this round)
out=$(payload_bash "cp evil.sh hooks/gates/evil.sh" | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "direct Bash write to hooks/gates/* -> ask" "$ok"

out=$(payload_write "hooks/gates/foo.py" "print(1)" | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "Write tool targeting hooks/gates/* -> ask" "$ok"

out=$(payload_bash "cp a.sh /tmp/somewhere/b.sh" | bash "$GUARD" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "unrelated benign write -> exit 0, no output" "$ok"

# Round-3 port regressions/gaps (found by a subagent_type:kbg:silent-failure-hunter
# re-verification dispatch against worktree-guard.py the same day, then confirmed to
# also be exploitable here by direct reproduction against the unmodified file before
# porting the fix). Each pairs a must-ask positive case with the closest negative case,
# same discipline as test-worktree-guard.sh's battery: a fix that only stops the bypass
# but starts false-denying benign commands is not actually fixed.
BATTERY=(
  "newline-joined write on 2nd line|$(printf 'echo hello\nsed -i "" "s/x/y/" hooks/gates/irrecoverable.sh')|ask"
  "heredoc body w/ unbalanced quote, write after|$(printf "cat <<EOF > /tmp/x.txt\nit%ss here\nEOF\ncp evil.sh hooks/gates/evil2.sh" "'")|ask"
  "ANSI-C quoted target|echo x > \$'hooks/gates/evil5.sh'|ask"
  "hyphenated heredoc delimiter, write after|$(printf 'cat <<MY-EOF\nbody\nMY-EOF\ncp evil.sh hooks/gates/evil6.sh')|ask"
  "unquoted \$TARGETDIR target|cp evil.sh \$TARGETDIR/evil3.sh|ask"
  "unquoted ~ target|cp evil.sh ~/evil4.sh|ask"
  "comment mentions a protected-looking path, no real write|cp a.sh b.sh # update hooks/gates/x.sh|noask"
  "comment contains a fake redirect symbol|ls -la # see > hooks/gates/notes.txt for details|noask"
  "write on same line before a trailing comment, target NOT protected|cp a.sh /tmp/b.sh # note|noask"
)

for row in "${BATTERY[@]}"; do
  desc="${row%%|*}"
  rest="${row#*|}"
  cmd="${rest%|*}"
  expect="${rest##*|}"
  out=$(payload_bash "$cmd" | TARGETDIR="$ROOT/hooks/gates" HOME="$ROOT/hooks/gates" bash "$GUARD" 2>/dev/null)
  got_ask=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && got_ask=0
  ok=1
  if [ "$expect" = "ask" ] && [ "$got_ask" -eq 0 ]; then ok=0; fi
  if [ "$expect" = "noask" ] && [ "$got_ask" -eq 1 ]; then ok=0; fi
  check "battery: $desc" "$ok"
done

# Round-4 regression tests (found 2026-08-04 by a subagent_type:kbg:silent-failure-hunter
# dispatch covering both worktree-guard.py and verifier-protect.sh together -- a different
# idiom family than the same-day preprocessing fixes above: git apply/am and patch never
# scanned diff CONTENT for the real +++ b/<path> target, and bare tar extraction (no -C)
# yielded no candidate at all. All 3 were already disclosed as deferred follow-ups in this
# repo's own v0.68.171 CHANGELOG entry; closed here as their own scoped piece of work.
DIFF_FILE="${TMPDIR:-/tmp}/kbg-vp-round4-evil.diff"
printf -- '--- a/hooks/gates/irrecoverable.sh\n+++ b/hooks/gates/irrecoverable.sh\n@@ -1,1 +1,1 @@\n-x\n+evil\n' > "$DIFF_FILE"
BENIGN_DIFF="${TMPDIR:-/tmp}/kbg-vp-round4-benign.diff"
printf -- '--- a/README.md\n+++ b/README.md\n@@ -1,1 +1,1 @@\n-x\n+y\n' > "$BENIGN_DIFF"

out=$(payload_bash "git apply $DIFF_FILE" | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "git apply: real target lives in diff content, not argv -> ask" "$ok"

out=$(payload_bash "git apply $BENIGN_DIFF" | bash "$GUARD" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "git apply against a diff touching nothing protected -> exit 0, no false ask" "$ok"

# -C relocates where a relative in-diff target resolves. The first version of this fix
# dispatched into apply/am correctly for -C but still resolved the diff's relative target
# against the hook's own cwd -- confirmed the hard way while building this round's fix.
out=$(payload_bash "git -C $ROOT apply $DIFF_FILE" | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "git -C <dir> apply: -C resolves the diff target, not the hook's own cwd -> ask" "$ok"

out=$(payload_bash "patch -p1 < $DIFF_FILE" | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "patch, stdin-piped: real target lives in diff content, not argv -> ask" "$ok"

out=$(payload_bash "patch --directory=$ROOT -p1 < $DIFF_FILE" | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "patch --directory=: real target resolves against it, not bare cwd -> ask" "$ok"

out=$( (cd "$ROOT/hooks/gates" && payload_bash "tar xf archive.tar" | bash "$GUARD") 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "tar xf, no -C, cwd itself is inside hooks/gates -> ask" "$ok"

out=$(payload_bash "tar xf archive.tar" | bash "$GUARD" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "tar xf, no -C, cwd is repo root (documented residual gap, not a regression) -> exit 0" "$ok"

# path-hardcode block still wins over ask (folded gate, pre-existing, sanity only).
# Built via concatenation, not a literal contiguous string, so this test file itself
# does not trip the very gate it is testing when this test file is written/edited.
hardcoded_snippet="path=/Us""ers/someone/x"
out=$(payload_write "hooks/gates/newfile.sh" "$hardcoded_snippet" | bash "$GUARD" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "hardcoded /Users/ path in .sh content -> block exit 2 (wins over ask)" "$ok"

echo ""
total=$((pass + fail))
echo "=== $pass/$total passed ==="
[ "$fail" -eq 0 ] && exit 0 || exit 1
