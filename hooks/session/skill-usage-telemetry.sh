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

# Two adversarial-audit fixes (2026-08-25, #90 independent review):
#   - tool_input.skill can be present but the WRONG type (a number, an
#     object) rather than merely missing/null; `// "unknown"` alone only
#     covers missing/null, so a wrong-typed value used to throw inside
#     `split(":")` -- a jq error swallowed by 2>/dev/null, silently
#     DROPPING the row entirely instead of falling back to "unknown" like
#     every other malformed-input path here does. Now type-checked first.
#   - an unnamespaced skill (no ":" at all -- several real skills in this
#     fleet have no plugin prefix) used to fall through split(":")[0] and
#     report plugin == skill, showing up in the health panel as its own
#     fake single-skill "plugin". Now reported as "unnamespaced" instead.
jq -c --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
  (if (.tool_input.skill? | type) == "string" and (.tool_input.skill | length) > 0
   then .tool_input.skill else "unknown" end) as $skill |
  {
    ts: $ts,
    session_id: (.session_id // "unknown"),
    skill: $skill,
    plugin: (if ($skill | contains(":")) then ($skill | split(":")[0]) else "unnamespaced" end)
  }
' <<<"$payload" >>"$log_dir/skill-usage.jsonl" 2>/dev/null

exit 0
