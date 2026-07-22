#!/usr/bin/env bash
# Advisory: after a plan is approved (ExitPlanMode succeeds), nudge
# dispatching kbg:plan-reviewer for consequential plans before implementing.
# PostToolUse hook, matcher "ExitPlanMode" -- fires only on approval (a
# manual reject/cancel never reaches PostToolUse; the tool never "completes
# successfully" on a deny). Never blocks; always exits 0. Output goes via
# hookSpecificOutput.additionalContext (PostToolUse's structured-output
# field), not plain stdout -- unlike flow-nudge.sh's UserPromptSubmit shape.
#
# Why a hook, not just doctrine text: METHODOLOGY.md's plan-mode rule is
# injected once per SessionStart/compact, not anchored to this specific
# event -- the same gap flow-nudge.sh was built to close for the analogous
# "plan before you edit" reminder. See docs/reference/decision-doctrine-map.md's
# "Plan -> implement" row for the full routing this points at.
#
# Verified against docs/en/hooks.md + docs/en/tools-reference.md (2026-07-22):
# tool_response.plan carries the approved plan text directly on stdin --
# no need to re-read the plan file (which gets overwritten on the next
# plan-mode cycle in the same session, see cc-plan-mode-single-file-per-session
# memory), and this hook never quotes the plan text back anyway.
set -uo pipefail

# shellcheck disable=SC2016  # single quotes are intentional: this is Python code, not shell
python3 -c '
import json, sys

try:
    d = json.load(sys.stdin)
    plan = d.get("tool_response", {}).get("plan", "")
except Exception:
    plan = ""

if not plan:
    sys.exit(0)

nudge = (
    "[kbg:plan-review-nudge] Plan approved — if this is a consequential plan "
    "(multi-file / one-way door / unfamiliar subsystem), consider dispatching "
    "kbg:plan-reviewer against the approved plan text before implementing. "
    "Paste the plan text into the prompt directly — do not have the agent "
    "re-read the plan file, it gets overwritten on the next plan-mode cycle "
    "this session. See docs/reference/decision-doctrine-map.md, the "
    "\"Plan -> implement\" row. Skip for routine/small plans. The nudge is "
    "advisory; the model judges."
)

print(json.dumps(
    {"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": nudge}},
    ensure_ascii=False,
))
' 2>/dev/null

exit 0
