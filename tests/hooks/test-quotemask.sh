#!/usr/bin/env bash
# _quotemask.py unit + drift tests. Both subagent-git-guard.py and
# test-integrity.py import mask_quotes from this shared module (2026-09-20,
# deferred finding #10 follow-up, after the two files' own copies drifted
# into byte-identical duplicates that each independently missed the same
# "#"-comment bug). This test proves: (1) the shared module itself handles
# the known bug classes, and (2) both consumers actually import it rather
# than silently falling back to a stale inline copy.
# Run standalone: bash tests/hooks/test-quotemask.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
QM="$ROOT/hooks/gates/_quotemask.py"

pass=0
fail=0

check() {
  local desc="$1" ok="$2"
  if [ "$ok" -eq 0 ]; then
    echo "  ✅ $desc"
    pass=$((pass + 1))
  else
    echo "  ❌ $desc" >&2
    fail=$((fail + 1))
  fi
}

mask() {
  python3 -c "
import sys
sys.path.insert(0, '$ROOT/hooks/gates')
from _quotemask import mask_quotes
print(mask_quotes(sys.argv[1]), end='')
" "$1"
}

echo "=== _quotemask.py: mask_quotes() unit tests ==="
echo ""

OUT=$(mask 'git reset --hard')
ok=1; [ "$OUT" = "git reset --hard" ] && ok=0
check "plain command, no quotes -> unchanged" "$ok"

OUT=$(mask "echo 'a; b'")
ok=1; [[ "$OUT" != *";"* ]] && ok=0
check "separator inside single quotes is masked" "$ok"

OUT=$(mask "echo hi # don't remove
git reset --hard")
ok=1; [[ "$OUT" == *$'\n'"git reset --hard" ]] && ok=0
check "comment apostrophe before real content: 'git reset --hard' survives on its own line" "$ok"

OUT=$(mask 'git reset --hard # comment after, with an apostrophe don'"'"'t matter')
ok=1; [[ "$OUT" == "git reset --hard"* ]] && ok=0
check "comment apostrophe AFTER the real command: command text stays intact" "$ok"

# 2026-09-21 deep-audit: ")" is a bash metacharacter, so "#" right after it
# starts a comment ("(true)#don't" is a comment from "#" on), but it was
# missing from _WORD_BOUNDARY_CHARS -- the apostrophe opened a fake
# single-quote span that masked the real "git stash" on the next line away.
OUT=$(mask "(true)#don't
git stash")
ok=1; [[ "$OUT" == *$'\n'"git stash" ]] && ok=0
check "comment right after a ')' (metacharacter): 'git stash' on the next line survives" "$ok"

# Control: a backtick is NOT a metacharacter, so "\`true\`#don't" is one word
# and the "'" really does open a quote in bash -- must still be masked.
OUT=$(mask "\`true\`#don't
git stash")
ok=1; [[ "$OUT" != *"git stash" ]] && ok=0
check "control: '#' right after a backtick is not a comment, the quote span still masks" "$ok"

# GH #157 sibling (2026-09-21): a backslash-escaped quote OUTSIDE a span is
# a literal character in real bash, never a span opener -- an odd backslash
# run escapes the quote, an even run is literal backslashes and leaves the
# quote live. The old masker opened a span at any bare quote, so
# `echo \" ; git stash` masked the real "git stash" away: a bypass.
OUT=$(mask 'echo \" ; git stash')
ok=1; [[ "$OUT" == *"; git stash" ]] && ok=0
check "escaped double quote outside a span is literal (odd run): 'git stash' after it survives" "$ok"

OUT=$(mask "echo \\' ; git stash")
ok=1; [[ "$OUT" == *"; git stash" ]] && ok=0
check "escaped single quote outside a span is literal (odd run): 'git stash' after it survives" "$ok"

OUT=$(mask 'echo \\" ; git stash"')
ok=1; [[ "$OUT" != *"git stash"* ]] && ok=0
check "even backslash run before a double quote leaves the quote live: span still masks" "$ok"

OUT=$(mask "echo \\\\' ; git stash'")
ok=1; [[ "$OUT" != *"git stash"* ]] && ok=0
check "even backslash run before a single quote leaves the quote live: span still masks" "$ok"

OUT=$(mask "echo '\\' ; git stash")
ok=1; [[ "$OUT" == *"; git stash" ]] && ok=0
check "backslash inside single quotes is literal: the span closes at the next quote, 'git stash' survives" "$ok"

OUT=$(mask 'echo "\" ; git stash"')
ok=1; [[ "$OUT" != *"git stash"* ]] && ok=0
check "control: backslash-escaped quote INSIDE a double-quoted span stays inside it" "$ok"

echo ""
echo "=== drift check: both consumers actually import the shared module ==="
echo ""

ok=1; command grep -q "from _quotemask import mask_quotes" "$ROOT/hooks/gates/subagent-git-guard.py" && ok=0
check "subagent-git-guard.py imports mask_quotes from _quotemask" "$ok"

ok=1; command grep -q "from _quotemask import mask_quotes" "$ROOT/hooks/gates/test-integrity.py" && ok=0
check "test-integrity.py imports mask_quotes from _quotemask" "$ok"

echo ""
echo "=== fallback: gates keep working if _quotemask.py is ever unavailable ==="
echo ""

trap 'mv "$QM.disabled-test" "$QM" 2>/dev/null || true' EXIT
mv "$QM" "$QM.disabled-test"
OUT=$(printf '%s' '{"tool_name":"Bash","agent_id":"x","tool_input":{"command":"git reset --hard"}}' | python3 "$ROOT/hooks/gates/subagent-git-guard.py" 2>/dev/null; echo "rc=$?")
mv "$QM.disabled-test" "$QM"
ok=1; [[ "$OUT" == *"rc=2"* ]] && ok=0
check "subagent-git-guard.py still denies via its inline fallback when _quotemask.py is missing" "$ok"

echo ""
total=$((pass + fail))
echo "=== $pass/$total passed ==="
[[ "$fail" -eq 0 ]] && exit 0 || exit 1
