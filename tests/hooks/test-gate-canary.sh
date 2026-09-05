#!/usr/bin/env bash
# scripts/gate-canary.sh (run by pre-commit on staged gates) must pass on the
# shipped gates and fail on the two slips that locked Bash machine-wide on
# 2026-09-05: a NameError in irrecoverable.py, and an apostrophe inside a
# gate's embedded python string (GH #146 shape).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/../.."
CANARY="$ROOT/scripts/gate-canary.sh"
pass=0; fail=0
check() { if [ "$2" -eq 0 ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }

tmp=$(mktemp -d)
trap '[ -n "$tmp" ] && trash "$tmp" 2>/dev/null || true' EXIT
fresh() { cp "$ROOT"/hooks/gates/*.sh "$ROOT"/hooks/gates/*.py "$tmp"/; }

bash "$CANARY" "$ROOT/hooks/gates" >/dev/null 2>&1
check "shipped gates pass the canary" $?

fresh
python3 -c "
import sys; p = sys.argv[1]; s = open(p).read()
s = s.replace('import json, os, re, shlex, sys', 'import json, os, re, shlex, sys\nundefined_name_xyz()', 1)
open(p, 'w').write(s)" "$tmp/irrecoverable.py"
bash "$CANARY" "$tmp" >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ]; check "injected NameError in irrecoverable.py fails the canary" $?

fresh
python3 -c "
import sys; p = sys.argv[1]; s = open(p).read()
s = s.replace('import json, re, sys', 'import json, re, sys  # it' + chr(39) + 's', 1)
open(p, 'w').write(s)" "$tmp/subagent-git-guard.sh"
bash "$CANARY" "$tmp" >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ]; check "apostrophe inside an embedded python string fails the canary" $?

echo ""
echo "test-gate-canary: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
