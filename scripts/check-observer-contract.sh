#!/usr/bin/env bash
# check-observer-contract.sh [plugin-dir] — GH #443: fail when hooks/mod/cost-ledger.ts stops being
# an observer. Two layers, because `claude plugin validate --json` (2.1.289) reports only what a
# module hooks and which `$.` calls it makes, as notes on the hooks.json entry:
#   "./mod/cost-ledger.ts hooks: turn.complete"
#   "./mod/cost-ledger.ts calls: $.process.run, $.session.id, ..."
#   1. validate notes: every hook must be turn.complete, and no call may be an ask/deny/permission
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
for h in (x.strip() for line in hooks for x in line.split(",")):
    if h != "turn.complete":
        bad.append(f"registers {h}; only turn.complete observers are allowed")
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
hits="$(sed 's#//.*##' "$MOD" | /usr/bin/grep -nE '\b(deny|ask|allow)[[:space:]]*:|next\([[:space:]]*\{')"
if [ -n "$hits" ]; then
  printf '%s\n' "$hits" | sed 's/^/observer-contract: deny\/ask\/rewrite in source: /'
  rc=1
fi

[ "$rc" -eq 0 ] && echo "observer-contract: cost-ledger.ts is an observer"
exit "$rc"
