#!/usr/bin/env bash
# Summarizes the gate-verdict journal (hooks/dispatch-pretooluse.py's
# _journal()) for recursive-improve's Observe step: per-gate ask/deny/defer
# counts since the journal started. The journal has no free-text reason field
# -- this is frequency signal only, not a "why". Graceful when the journal
# doesn't exist yet (fresh environment, or nothing non-"allow" has fired).
set -uo pipefail

log="${HOME}/.local/share/kbg/metrics/gate-decisions.jsonl"

if [[ ! -f "$log" ]]; then
  echo "no gate-verdict journal yet (no ask/deny/defer recorded in this environment)"
  exit 0
fi

python3 -c '
import json, collections, sys

path = sys.argv[1]
counts = collections.Counter()
total = 0
oldest = newest = None

with open(path) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            row = json.loads(line)
        except ValueError:
            continue
        total += 1
        counts[(row.get("id", "?"), row.get("decision", "?"))] += 1
        ts = row.get("ts")
        if ts:
            oldest = ts if oldest is None or ts < oldest else oldest
            newest = ts if newest is None or ts > newest else newest

if total == 0:
    print("gate-verdict journal exists but is empty")
    sys.exit(0)

print(f"{total} non-allow verdicts, {oldest} to {newest}")
for (gate_id, decision), n in sorted(counts.items(), key=lambda kv: -kv[1]):
    print(f"{n:4d}  {decision:6s}  {gate_id}")
' "$log"
