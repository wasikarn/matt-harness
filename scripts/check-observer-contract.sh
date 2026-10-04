#!/usr/bin/env bash
# check-observer-contract.sh [plugin-dir] — GH #443: fail when hooks/mod/cost-ledger.ts stops being
# an observer. Two layers, because `claude plugin validate --json` (2.1.289) reports only what a
# module hooks and which `$.` calls it makes, as notes on the hooks.json entry:
#   "./mod/cost-ledger.ts hooks: turn.complete"
#   "./mod/cost-ledger.ts calls: $.process.run, $.session.id, ..."
#   1. validate notes: every hook must be an observer event (turn.complete, session.start,
#      skill.prompt; #442/#444 added the last two), and no call may be an ask/deny/permission
#      surface ($.ui.ask is the one this build has). A missing hooks note fails: the shape changed.
#   2. static scan of the source: a deny/ask/allow result (`{ deny: ... }`) and a rewrite
#      (`next({ ...e, x })`) are return values, which the notes cannot show.
# Wired into run-gauntlet.sh's validate layer; tests/scripts/test-observer-contract.sh covers it.
set -uo pipefail
DIR="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
MOD="$DIR/hooks/mod/cost-ledger.ts"
[ -f "$MOD" ] || { echo "observer-contract: $MOD not found" >&2; exit 1; }
rc=0

if command -v claude >/dev/null; then
  json="$(cd "$DIR" && claude plugin validate .claude-plugin/plugin.json --json 2>/dev/null)"
  printf '%s' "$json" | python3 -c '
import json, re, sys
try:
    d = json.load(sys.stdin)
except ValueError as e:
    sys.exit(f"observer-contract: validate --json did not parse: {e}")
notes = [n for c in d.get("contents", []) for n in c.get("notes", []) if isinstance(n, str)]
mod = [n for n in notes if n.split(" ", 1)[0].endswith("mod/cost-ledger.ts")]
hooks = [n.split(" hooks: ", 1)[1] for n in mod if " hooks: " in n]
calls = [n.split(" calls: ", 1)[1] for n in mod if " calls: " in n]
bad = []
if not hooks:
    bad.append("no \"cost-ledger.ts hooks:\" note in validate --json (CLI output shape changed?)")
observers = ("turn.complete", "session.start", "skill.prompt")
allowed = ", ".join(observers)
for h in (x.strip() for line in hooks for x in line.split(",")):
    if h not in observers:
        bad.append(f"registers {h}; only observer events ({allowed}) are allowed")
for c in (x.strip() for line in calls for x in line.split(",")):
    if re.search(r"ask|deny|allow|permission|decision", c, re.I):
        bad.append(f"calls {c}, a decision surface")
for b in bad:
    print("observer-contract:", b)
sys.exit(1 if bad else 0)
' || rc=1
else
  echo "observer-contract: SKIP validate-notes layer (no claude CLI); static scan only"
fi

# Strip // comments so the module's own "never denies, asks, rewrites" prose cannot trip the scan.
hits="$(sed 's#//.*##' "$MOD" | /usr/bin/grep -nE '\b(deny|ask|allow)[[:space:]]*:')"
if [ -n "$hits" ]; then
  printf '%s\n' "$hits" | sed 's/^/observer-contract: deny\/ask\/rewrite in source: /'
  rc=1
fi
# Rewrites: a whole-file scan, so a next( split across lines or fed a variable is still seen.
# Comments and string contents are blanked (newlines kept, so line numbers hold); every next(
# call's balanced-paren argument must be exactly the handler's event parameter `e`.
python3 - "$MOD" <<'PY' || rc=1
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
out, i, n = [], 0, len(src)
while i < n:
    c = src[i]
    if src.startswith("//", i):
        j = src.find("\n", i)
        i = n if j < 0 else j
    elif src.startswith("/*", i):
        j = src.find("*/", i + 2)
        j = n if j < 0 else j + 2
        out.append(re.sub(r"[^\n]", " ", src[i:j])); i = j
    elif c in "'\"`":
        j = i + 1
        while j < n and src[j] != c:
            j += 2 if src[j] == "\\" else 1
        out.append(c + re.sub(r"[^\n]", " ", src[i + 1:j]) + c); i = j + 1
    else:
        out.append(c); i += 1
code = "".join(out)
bad = 0
for m in re.finditer(r"(?<![\w$.])next\s*\(", code):
    depth, j = 1, m.end()
    while j < len(code) and depth:
        depth += {"(": 1, ")": -1}.get(code[j], 0); j += 1
    arg = code[m.end():j - 1]
    if arg.strip() != "e":
        bad = 1
        line = code.count("\n", 0, m.start()) + 1
        print(f"observer-contract: deny/ask/rewrite in source: L{line}: next({' '.join(arg.split())})")
sys.exit(bad)
PY

[ "$rc" -eq 0 ] && echo "observer-contract: cost-ledger.ts is an observer"
exit "$rc"
