#!/bin/bash
# run-report.sh <run-id> — re-render an L3 `--auto` run from the governance
# journal (CLAUDE.md §The operating model (was L3 bounded autonomy, retired) §E). Read-only. The journal is the durable per-cycle record
# (event=l3_cycle, fields.run_id + iteration + outcome); this is its query view,
# the companion to the human-written .scratch/l3-runs/<id>/session-audit-trail.md
# at Gate-2 review time. Degrades gracefully when jq or the journal is absent.
set -uo pipefail

RID="${1:-}"
[ -n "$RID" ] || { echo "usage: run-report.sh <run-id>" >&2; exit 2; }

JOURNAL="${CLAUDE_JOURNAL_PATH:-$HOME/.claude/governance-events.jsonl}"
command -v jq >/dev/null 2>&1 || { echo "jq not found — cannot query the journal" >&2; exit 1; }
[ -f "$JOURNAL" ] || { echo "no governance journal at $JOURNAL" >&2; exit 1; }

echo "=== L3 run report: $RID ==="
printf 'iter\toutcome\tfiles\tfailing_checks\n'
jq -r --arg rid "$RID" '
  select(.event == "l3_cycle" and .fields.run_id == $rid)
  | [ (.fields.iteration // "?"|tostring),
      (.fields.outcome // "?"),
      (.fields.files // "" | if type=="array" then join(",") else tostring end),
      (.fields.failing_checks // "" | if type=="array" then join(",") else tostring end)
    ] | @tsv
' "$JOURNAL" | sort -n -k1

green=$(jq -r --arg rid "$RID" 'select(.event=="l3_cycle" and .fields.run_id==$rid and .fields.outcome=="green")|.id' "$JOURNAL" | grep -c . || true)
red=$(jq -r --arg rid "$RID" 'select(.event=="l3_cycle" and .fields.run_id==$rid and .fields.outcome=="red")|.id' "$JOURNAL" | grep -c . || true)
skip=$(jq -r --arg rid "$RID" 'select(.event=="l3_cycle" and .fields.run_id==$rid and .fields.outcome=="skipped")|.id' "$JOURNAL" | grep -c . || true)
echo "---"
echo "green=$green red=$red skipped=$skip"
