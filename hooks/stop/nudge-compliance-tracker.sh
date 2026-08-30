#!/usr/bin/env bash
# Stop: measure flow-nudge compliance -- did a plan-first nudge get acted on
# (EnterPlanMode, or a genuine advisor() consultation) before the NEXT nudge
# fired, or ignored.
#
# Closes the gap named in mh-memory/requirement-analyst-flow-nudge-v0591-2026-07-18.md
# and re-surfaced by the 2026-08-30 article audit: flow-nudge.sh (UserPromptSubmit)
# fires deterministically -- a real, empirically-tuned Cue -- but nothing measured
# whether the model actually acted on it, only that it fired. Knowledge + Cue without
# a Feedback signal doesn't strengthen the behavior over time.
#
# Scope: flow-nudge's plan-first nudge only, not plan-review-nudge.sh's post-approval
# nudge -- a distinct compliance question (did plan-reviewer get dispatched after plan
# approval) left as a follow-up, not bundled in here.
#
# Detection shapes below were read off a real transcript, not guessed (advisor()'s own
# review of the first draft caught that "advisor" never appears as a tool_use name --
# an untested assumption would have silently zeroed this metric forever, the same
# check62 silent-clean-on-crash class this repo's own post-mortems warn about):
#   - EnterPlanMode: {type:"assistant", message.content[]: {type:"tool_use", name:"EnterPlanMode"}}
#   - advisor():     {type:"assistant", message.usage.iterations[]: {type:"advisor_message"}}
#     (iterations, not a top-level tool_use -- advisor runs as a distinct consultation
#     turn, not an ordinary tool call; the same logical call can appear on more than one
#     transcript line as it streams, harmless here since only "any" match is checked)
# Each fire is bounded to before the NEXT fire (or end-of-transcript for the last one) --
# an earlier unbounded "any later response" version marked every prior fire compliant
# off a single response, which reads high and would never catch a truly ignored nudge.
#
# Re-derives from the full transcript every Stop (stateless, no counter file to corrupt
# or fall out of sync -- same convention as hooks/stop/cost-tracker.sh) and appends one
# row per Stop to nudge-compliance.jsonl. Each row's own fired/complied counts only ever
# grow within a session (re-derived from the whole transcript so far), so the LATEST row
# per session is found by max_by(.nudges_fired), not max_by(.timestamp) -- two Stop hooks
# firing in the same UTC second (async:true, back-to-back turns) can tie on timestamp and
# pick a stale, lower count; nudges_fired is monotonic within a session by construction and
# never ties on a real progression. Rolling compliance rate for a session:
#   jq -s '[.[] | select(.session_id=="<sid>")] | max_by(.nudges_fired) | .nudges_complied / (.nudges_fired // 1)' nudge-compliance.jsonl
# Across all sessions (last row per session_id, since rows accumulate per-Stop):
#   jq -s 'group_by(.session_id) | map(max_by(.nudges_fired)) | (map(.nudges_complied) | add) / (map(.nudges_fired) | add)' nudge-compliance.jsonl
#
# Known ceiling (2026-08-30 deep-audit): attachment.hookName, attachment.content, and
# message.usage.iterations[].type=="advisor_message" are real but internal, undocumented
# Claude Code transcript fields with no public schema guarantee -- the same class of risk
# hooks/advisory/plan-review-nudge.sh already names for tool_response.plan. If a future
# Claude Code version renames or relocates any of them, this hook keeps running, keeps
# exiting 0, and silently reports nudges_complied:0 forever -- indistinguishable from real
# non-compliance, with nothing else to catch it. No fix possible from inside this repo (the
# shape is CC's contract, not ours) -- tests/hooks/test-session-stop.sh's
# "nudge-compliance-tracker hook" section fixtures these exact field names, so it goes quiet
# in lockstep with the hook on a real schema change; re-run a live-fire smoke test (fire a
# real flow-nudge, call advisor() or EnterPlanMode, check nudge-compliance.jsonl) after any
# Claude Code version bump.
set -uo pipefail

payload=$(cat)

# Portability guard (#93): every extraction below is jq. Skip metrics entirely
# without it -- announced once per session by doctrine-bootstrap.sh's preflight,
# not per-stop (a Stop hook fires every turn).
if ! command -v jq >/dev/null 2>&1; then
  printf '%s' "$payload"
  exit 0
fi

transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null)
session_id=$(printf '%s' "$payload" | jq -r '.session_id // "default"' 2>/dev/null)

if [[ -z "$transcript" || ! -f "$transcript" ]]; then
  printf '%s' "$payload"
  exit 0
fi

metrics_dir="$HOME/.local/share/kbg/metrics"
mkdir -p "$metrics_dir"
metrics_file="$metrics_dir/nudge-compliance.jsonl"

# -nRc + try fromjson (not plain -nc): one malformed/truncated transcript line
# must not kill the whole pass -- same defensive shape as cost-tracker.sh's
# emit_rows, adopted after check62's silent-crash post-mortem
# (docs/post-mortems/check62-allowlist-crash-2026-08-21.md) named the general
# failure class this guards against.
row=$(jq -nRc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg sid "$session_id" '
  ([inputs | try fromjson] | to_entries) as $idx
  | [ $idx[] | select(.value.type == "attachment"
                       and .value.attachment.type == "hook_success"
                       and .value.attachment.hookName == "UserPromptSubmit"
                       and (.value.attachment.content // "" | startswith("[mh:flow-nudge] Non-trivial work detected")))
      | .key ] as $fires
  | [ $idx[] | select(.value.type == "assistant"
                       and (any((.value.message.content // [])[]?;
                                .type == "tool_use" and .name == "EnterPlanMode")
                            or any((.value.message.usage.iterations // [])[]?;
                                   .type == "advisor_message")))
      | .key ] as $responses
  | ($fires | length) as $fired
  | ([ range(0; $fired) as $i
       | $fires[$i] as $f
       | (if $i + 1 < $fired then $fires[$i + 1] else infinite end) as $next
       | select(any($responses[]; . > $f and . < $next)) ]
     | length) as $complied
  | { timestamp: $ts, session_id: $sid, nudges_fired: $fired, nudges_complied: $complied }
' "$transcript" 2>/dev/null) || row=''

# Refuse to append through a symlink -- same guard as cost-tracker.sh.
if [[ -n "$row" && ! -L "$metrics_file" ]]; then
  printf '%s\n' "$row" >> "$metrics_file"
fi

printf '%s' "$payload"
exit 0
