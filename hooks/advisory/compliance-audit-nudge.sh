#!/usr/bin/env bash
# Advisory: after a git commit, if a plan was approved earlier this session,
# remind the model to tell the user that /mh:compliance-audit exists --
# never to dispatch it (skills/review/compliance-audit/SKILL.md is
# disable-model-invocation:true; the reason: "costly multi-agent fan-out
# that gates a done-declaration -- user decides when the audit runs, not
# the model"). PostToolUse hook, matcher "Bash" -- fires on tool completion
# regardless of the commit's own exit code (a failed/empty commit still
# nudges; low-impact, same advisory-noise tolerance as every other nudge
# here). Never blocks; always exits 0.
#
# Why PostToolUse:Bash and not Stop: Stop fires on every turn end (this
# hook only cares about ones that just committed); Stop DOES support
# hookSpecificOutput.additionalContext as of Claude Code 2.1.163 (the
# channel this hook relies on -- the same one plan-review-nudge.sh uses),
# but that alone doesn't justify the switch here -- the one existing Stop
# hook (stop/cost-tracker.sh) is wired async:true (dead for any
# output-based contract), and a sync Stop hook emitting continuation-style
# output needs the stop_hook_active loop guard, which has zero precedent
# in this repo. PostToolUse:Bash matched on a commit is a much closer
# analog to ExitPlanMode's cleanliness -- a real, deterministic, low-noise
# "this unit of work is considered done" signal.
#
# Bash-first, python only on a double hit ("grep gates, python confirms"):
# matcher "Bash" fires on EVERY Bash call in every repo running this
# plugin, so a python3 spawn inside the fast path (this repo's own commit
# convention is frequent direct pushes, no feature branches) would repay
# an interpreter-startup + full-transcript-scan cost on most commits in a
# session. Detection order: (1) pure-bash sed/grep check that the command
# looks like `git commit` (learn-nudge.sh's own extraction idiom) --
# anchored so `git commit-graph`/`git commit-tree` don't false-match; no
# match -> exit 0, zero interpreter spawns. (2) pure-bash extraction of
# transcript_path (same idiom); missing/unreadable -> exit 0. (3) a cheap
# grep prefilter for the literal string ExitPlanMode anywhere in the
# transcript -- this is the same naive check known to false-positive on
# deferred_tools_delta attachment entries (documented in
# plan-review-nudge.sh's own design notes), which is fine here since it's
# a gate, not the final answer; no match anywhere -> exit 0, skipping the
# expensive parse entirely for the common case of a session that never
# touched plan mode. (4) only on a prefilter hit: python3, reading the
# transcript line-by-line with a per-line try/except (cost-tracker.sh's
# own resilience pattern), confirming the precise structural signal -- an
# assistant-role entry whose message.content[] carries a tool_use block
# with name=="ExitPlanMode" and a non-empty input.plan. Measured against a
# real 79MB/27,125-line transcript in this environment: the full precise
# parse costs ~0.3s: only paid when both bash gates already hit.
#
# No suppression/state tracking -- matches this repo's other advisory
# nudges' lack of an "already nudged" memory. Named cost: a long session with one
# early plan approval and several later, unrelated commits can re-fire
# this more than once. Advisory, cheap to ignore, same risk profile as
# every other nudge in this repo.
#
# Known limitation, not fixed: whether a Task-dispatched subagent's own
# PostToolUse payload carries a transcript_path distinct from the parent
# session's is unverified -- if it does, a subagent that commits on the
# parent's behalf would never see the parent's ExitPlanMode event (a false
# negative). Judged low-probability (this repo's convention is commits
# happen in the driving session, reinforced by
# gate:task:complete-separation's maker!=checker completion ownership) and
# not verifiable without a live subagent dispatch.
#
# Built after an adversarial plan-review pass caught a Critical finding on
# the first draft of this hook's design: the nudge text must never use a
# "consider dispatching" verb, because compliance-audit carries
# disable-model-invocation and self-dispatch is exactly what that flag
# forbids. See docs/reference/decision-doctrine-map.md's
# "Implementation -> verify" row for the full routing this points at.
#
# Restored 2026-08-25 (revived alongside plan-reviewer/plan-review-nudge.sh
# after both were judged wrongly deleted 2026-08-24) -- routed through
# dispatch-single.sh this time, which didn't exist when this hook was
# first written.
set -uo pipefail

INPUT=$(cat)
[ -n "$INPUT" ] || exit 0

# Truncate to the head of the payload, before "tool_response" -- tool_input
# always serializes first in this hook's JSON schema. Bounding the greedy
# sed match to this window stops a decoy "command"/"transcript_path" key
# inside tool_response's own stdout/stderr text (e.g. a test script that
# echoes JSON-shaped output) from winning over the real tool_input value.
INPUT_HEAD=$(printf '%s' "$INPUT" | sed 's/"tool_response".*//')

COMMAND=$(printf '%s' "$INPUT_HEAD" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
[ -n "$COMMAND" ] || exit 0
printf '%s' "$COMMAND" \
  | /usr/bin/grep -qE '(^|[^a-zA-Z0-9_-])git[[:space:]]+commit([^a-zA-Z0-9_-]|$)' \
  || exit 0

TRANSCRIPT=$(printf '%s' "$INPUT_HEAD" | sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
[ -n "$TRANSCRIPT" ] && [ -r "$TRANSCRIPT" ] || exit 0

/usr/bin/grep -q '"name"[[:space:]]*:[[:space:]]*"ExitPlanMode"' "$TRANSCRIPT" 2>/dev/null || exit 0

# shellcheck disable=SC2016  # single quotes are intentional: this is Python code, not shell
python3 -c '
import json, sys

transcript_path = sys.argv[1]
found_plan = False
try:
    with open(transcript_path, encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except Exception:
                continue
            if entry.get("type") != "assistant":
                continue
            content = entry.get("message", {}).get("content", [])
            if not isinstance(content, list):
                continue
            for block in content:
                if (
                    isinstance(block, dict)
                    and block.get("type") == "tool_use"
                    and block.get("name") == "ExitPlanMode"
                    and block.get("input", {}).get("plan")
                ):
                    found_plan = True
                    break
            if found_plan:
                break
except Exception:
    sys.exit(0)

if not found_plan:
    sys.exit(0)

nudge = (
    "[mh:compliance-audit-nudge] A git commit landed after a plan was "
    "approved earlier this session. compliance-audit is "
    "disable-model-invocation:true — do not dispatch or invoke it "
    "yourself under any circumstance. If this was a consequential "
    "implementation (multi-file / one-way door / unfamiliar subsystem), "
    "tell the user they can run /mh:compliance-audit themselves to "
    "verify the diff against the approved plan. See "
    "docs/reference/decision-doctrine-map.md, the "
    "\"Implementation -> verify\" row. Skip for routine/small changes. "
    "The nudge is advisory; the model judges whether to mention it, "
    "never whether to run it."
)

print(json.dumps(
    {"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": nudge}},
    ensure_ascii=False,
))
' "$TRANSCRIPT" 2>/dev/null

exit 0
