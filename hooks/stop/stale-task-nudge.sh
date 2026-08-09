#!/usr/bin/env bash
# Stop: nudge the model when a task it created is still `in_progress` right as
# the turn ends, with nothing in this turn touching it — the exact shape of a
# real incident (2026-08-09): a task was marked in_progress, a final report
# delivered as the turn's last output, and TaskUpdate(completed) never called.
# Caught only because the user happened to ask "check tasks that are still open".
#
# Stop has no passive "just show a reminder, turn ends normally" lever — every
# field that puts text in front of the model (`decision: block`,
# `hookSpecificOutput.additionalContext`) forces one more visible agent turn
# (code.claude.com/docs/en/hooks.md, "Stop decision control" — confirmed via a
# dedicated claude-code-guide check before building this, not assumed). This
# hook deliberately accepts that cost: `additionalContext` reads as guidance,
# not an error, so it's the less disruptive of the two available levers.
# Async does NOT help here — an async hook's JSON is still parsed, but
# `additionalContext` is only delivered on the NEXT turn (hooks.md, "Run hooks
# in the background"), too late to matter once this turn has already ended —
# so this hook must run synchronous, not fire-and-forget like
# stop/cost-tracker.sh and stop/memory-audit-commit.sh.
#
# `stop_hook_active` guards against re-firing on the forced continuation this
# hook itself triggers (Claude Code hard-caps at 8 consecutive Stop blocks
# regardless, but this hook shouldn't rely on hitting that cap). A per-session,
# per-task marker file bounds it further to ONE nudge per stale task per
# session — without it, a task legitimately left in_progress across several
# real turns (nothing wrong, just still being worked) would re-nag on every
# single Stop until closed. This can't distinguish "genuinely still working"
# from "forgot" — that's semantic judgment a deterministic hook can't make;
# the dedup just keeps the false-positive case from being annoying more than
# once. Known, accepted gap, not hidden: see docs/reference/hook-lifecycle-
# contracts.md if this file is ever updated to reflect this hook.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

payload=$(cat)

stop_hook_active=$(printf '%s' "$payload" | jq -r '.stop_hook_active // false' 2>/dev/null)
[[ "$stop_hook_active" == "true" ]] && exit 0

transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null)
session_id=$(printf '%s' "$payload" | jq -r '.session_id // "default"' 2>/dev/null)
[[ -n "$transcript" && -f "$transcript" ]] || exit 0

# Last-write-wins status per taskId, filtered to in_progress. TaskUpdate
# always carries taskId directly in its input (unlike TaskCreate, whose
# assigned id only appears in the tool_result) — no tool_use/tool_result
# correlation needed.
stale=$(jq -nRc '
  [ inputs | try fromjson |
    select(.type == "assistant") |
    (.message.content // [])[]? |
    select(.type == "tool_use" and .name == "TaskUpdate") |
    .input |
    select(.status != null and .taskId != null) |
    { taskId: (.taskId | tostring), status: .status }
  ]
  | group_by(.taskId)
  | map({ taskId: .[0].taskId, status: (last).status })
  | map(select(.status == "in_progress"))
  | map(.taskId)
' "$transcript" 2>/dev/null) || exit 0
[[ -z "$stale" || "$stale" == "[]" ]] && exit 0

marker_dir="$HOME/.local/share/kbg/task-nudge-sessions"
mkdir -p "$marker_dir" 2>/dev/null

to_nudge=()
while IFS= read -r tid; do
  [[ -n "$tid" ]] || continue
  # taskId comes from the transcript (model-authored tool input), not a
  # trusted source — sanitize before it becomes part of a filesystem path,
  # rather than relying on the "-" separator + touch's no-mkdir-p behavior
  # to accidentally block traversal.
  tid_safe="${tid//[^A-Za-z0-9_-]/_}"
  marker="$marker_dir/${session_id}-${tid_safe}"
  [[ -e "$marker" ]] && continue
  touch "$marker" 2>/dev/null
  to_nudge+=("$tid")
done < <(printf '%s' "$stale" | jq -r '.[]' 2>/dev/null)

(( ${#to_nudge[@]} == 0 )) && exit 0

ids_csv=$(printf '#%s, ' "${to_nudge[@]}")
ids_csv="${ids_csv%, }"

jq -nc --arg ctx "Task list state: $ids_csv still shows status in_progress, with no TaskUpdate call for it recorded this turn." '
  { hookSpecificOutput: { hookEventName: "Stop", additionalContext: $ctx } }
'
exit 0
