#!/usr/bin/env bash
# PostToolUse(Skill): journal every skill invocation to
# ~/.local/share/kbg/metrics/skill-usage.jsonl — usage evidence (not "feel")
# for the future matt-skill vs harness-skill overlap cull (#90/T11). This
# event has no decision control here — audit logging only, never a gate.
#
# Scope note (2026-08-25 operator decision): records invocation counts only,
# no outcome/success field. No reliable success signal exists for a Skill
# call — it loads instructions into context, it doesn't return an inspectable
# result the way a Bash exit code does — and docs don't confirm PostToolUse
# even defines one for this tool. Fabricating a constant "outcome" just to
# satisfy a schema would be a false metric, not a health signal.
#
# ponytail: unbounded append, same precedent as instructions-loaded-journal.sh
# and hooks/stop/cost-tracker.sh — rotate/trim manually if it grows large.
set -uo pipefail

payload=$(cat)

log_dir="$HOME/.local/share/kbg/metrics"
mkdir -p "$log_dir"

jq -c --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
  (.tool_input.skill // "unknown") as $skill |
  {
    ts: $ts,
    session_id: (.session_id // "unknown"),
    skill: $skill,
    plugin: ($skill | split(":")[0])
  }
' <<<"$payload" >>"$log_dir/skill-usage.jsonl" 2>/dev/null

exit 0
