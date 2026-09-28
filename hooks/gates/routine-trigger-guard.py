#!/usr/bin/env python3
import json, sys

# GH-adjacent to #156: raise the int-string digit limit before parsing so an
# oversized unquoted int literal doesn't crash json.load() into this gate's
# fail-open except below (full rationale: codex-setup-guard.py).
if hasattr(sys, "set_int_max_str_digits"):
    sys.set_int_max_str_digits(0)

try:
    from _journal import journal
except Exception:
    def journal(*a, **k):
        pass

GATE_ID = "gate:tool:routine-trigger-guard"

try:
    d = json.load(sys.stdin)
except Exception as e:
    # Fail-safe = ALLOW: a parse error must not stall a legitimate call.
    print(f"[mh:gate] routine-trigger-guard: unparseable stdin, allowing ({e})", file=sys.stderr)
    sys.exit(0)

if not isinstance(d, dict):
    print("[mh:gate] routine-trigger-guard: non-object payload, allowing", file=sys.stderr)
    sys.exit(0)

tool_name = d.get("tool_name")
if tool_name not in ("RemoteTrigger", "CronCreate"):
    sys.exit(0)

# ask, not deny: creating/firing a scheduled or remote-triggered cloud
# session (a Routine) can be a legitimate, operator-approved action --
# ADR 0004 (docs/adr/0004-operator-authorized-routine-self-launch.md) names
# this exact gap (its own [R1 fix] to §4, item 6 in §5) as required future
# work: "nothing gates the model from creating or firing a Routine in the
# first place" today. This closes that gap for an interactive session, the
# same shape as Phase B's `gh pr merge` ask-tier rule in irrecoverable.py.
# It does not, and cannot, constrain a Routine that already exists and is
# running outside this Claude Code session -- see the ADR's §4 for why.
reason = (
    f"{tool_name} creates or fires a scheduled/remote cloud session (a Routine) that can push "
    "and open PRs with no operator present once it runs -- confirm this is operator-approved "
    "before proceeding (docs/adr/0004-operator-authorized-routine-self-launch.md, still "
    "status: proposed)."
)
print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                         "permissionDecision": "ask",
                                         "permissionDecisionReason": reason}}))
journal(GATE_ID, tool_name, "ask", d.get("session_id"))
