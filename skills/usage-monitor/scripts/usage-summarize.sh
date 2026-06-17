#!/usr/bin/env bash
# usage-summarize.sh — read the captured OTEL JSONL and format a per-agent
# cost breakdown for the current project. Companion to usage-monitor-capture.sh.
#
# Usage:
#   bash usage-summarize.sh                 # most recent session
#   bash usage-summarize.sh --last N        # last N sessions (default 1)
#   bash usage-summarize.sh --all           # all captured sessions for project
#   bash usage-summarize.sh --project-slug  # override project slug detection
#
# Output: a markdown table (per-agent calls + input/output tokens + parent)
# plus a totals row. Stdout only — no writes.

set -euo pipefail

# shellcheck source=../../_lib/err.sh
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../_lib/err.sh"

require_cmd jq

CWD="${CLAUDE_PROJECT_DIR:-$PWD}"
SLUG=$(echo "$CWD" | sed 's|^/||; s|/|-|g' | tr '[:upper:]' '[:lower:]' | cut -c1-80)

# Parse args
LAST_N=1
MODE="last"
while [ $# -gt 0 ]; do
  case "$1" in
    --last)     LAST_N="${2:-1}"; shift 2 ;;
    --last=*)   LAST_N="${1#*=}"; shift ;;
    --all)      MODE="all"; shift ;;
    --project-slug) SLUG="${2:-}"; shift 2 ;;
    -h|--help)
      sed -n '2,12p' "$0" | sed 's/^# *//'
      exit 0
      ;;
    *) err_usage "usage-summarize [--last N|--all|--project-slug SLUG]" ;;
  esac
done

USAGE_DIR="${HOME}/.claude/usage"
USAGE_FILE="${USAGE_DIR}/${SLUG}.jsonl"

if [ ! -r "$USAGE_FILE" ]; then
  echo "# Usage summary — ${SLUG}"
  echo ""
  echo "_No capture file at \`${USAGE_FILE}\`._"
  echo ""
  echo "To start capturing: export \`KBG_USAGE_MONITOR=1\` before launching Claude Code."
  exit 0
fi

# Pick the lines we want. --all = entire file; --last N = tail N.
if [ "$MODE" = "all" ]; then
  SESSIONS=$(cat "$USAGE_FILE")
else
  SESSIONS=$(tail -n "$LAST_N" "$USAGE_FILE")
fi

SESSION_COUNT=$(echo "$SESSIONS" | grep -c '^{' || true)
if [ "$SESSION_COUNT" = "0" ]; then
  echo "_No sessions captured yet for ${SLUG}._"
  exit 0
fi

echo "# Usage summary — ${SLUG}"
echo ""
if [ "$MODE" = "all" ]; then
  echo "_${SESSION_COUNT} session(s) captured._"
else
  echo "_Last ${SESSION_COUNT} session(s). Use \`--all\` for the full history._"
fi
echo ""

# Aggregate by agent_id across all selected sessions. Sum calls + token counts.
# Schema reminder: each line is { session_id, ts, spans: [{agent_id, parent_agent_id, ...}] }
SUMMARY=$(echo "$SESSIONS" | jq -s '
  [ .[] | .spans[]? ] as $all
  | ( [ $all[] | (.agent_id // "(main)") ] | unique ) as $agents
  | {
      agents: [
        $agents[] as $a
        | {
            agent_id:   $a,
            calls:      ([ $all[] | select((.agent_id // "(main)") == $a) ] | length),
            in_tokens:  ([ $all[] | select((.agent_id // "(main)") == $a) | (.input_tokens  // 0) ] | add),
            out_tokens: ([ $all[] | select((.agent_id // "(main)") == $a) | (.output_tokens // 0) ] | add),
            parents:    ([ $all[] | select((.agent_id // "(main)") == $a) | (.parent_agent_id // null) ] | unique | map(select(. != null)))
          }
      ],
      totals: {
        calls:      ($all | length),
        in_tokens:  ([ $all[] | (.input_tokens  // 0) ] | add),
        out_tokens: ([ $all[] | (.output_tokens // 0) ] | add)
      }
    }
')

echo "| Agent | Calls | Input tokens | Output tokens | Parents |"
echo "|-------|-------|--------------|---------------|---------|"
echo "$SUMMARY" | jq -r '
  def fmt: tostring | if length > 3 then (.[0:length-3] | fmt) + "," + .[length-3:] else . end;
  .agents[] | [
    .agent_id,
    .calls,
    (.in_tokens | fmt),
    (.out_tokens | fmt),
    (if (.parents | length) == 0 then "—" else (.parents | join(", ")) end)
  ] | "| " + join(" | ") + " |"
'

# Totals row in the same table shape.
echo "$SUMMARY" | jq -r '
  def fmt: tostring | if length > 3 then (.[0:length-3] | fmt) + "," + .[length-3:] else . end;
  "| **TOTAL** | " + (.totals.calls | fmt) + " | " + (.totals.in_tokens | fmt) + " | " + (.totals.out_tokens | fmt) + " | — |"
'

echo ""
echo "_Source: \`${USAGE_FILE}\`. Capture is opt-in via \`KBG_USAGE_MONITOR=1\`._"
