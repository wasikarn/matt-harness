#!/usr/bin/env bash
# Gate: a subagent may not mark its own task completed (maker≠checker).
# Reads the PreToolUse JSON payload from stdin; exits 2 to block.
#
# Why: the builder → validator chain (METHODOLOGY.md Rule 13) was
# enforced by prompt doctrine + TaskCreate/addBlockedBy ordering only —
# addBlockedBy gates *ordering*, but nothing computationally stopped the maker
# from marking its own task `completed` without the validator's pass. That is
# the maker-grading-its-own-work circularity the harness exists to forbid.
# Native CC (v2.1.142+) fires PreToolUse inside subagents with `agent_id`
# present (docs-confirmed against code.claude.com/docs/en/hooks, corrected
# 2026-08-31: an earlier version of this gate keyed on `agent_type`, which is
# ALSO set for a top-level `claude --agent <name>` main session — a real
# security-review finding), so the gate can tell an actual subagent from the
# main session without an artifact file or an allowlist.
#
# Rule: deny TaskUpdate(status="completed") whenever `agent_id` is present
# (any subagent). The main session (no `agent_id`, whether or not it was
# started with --agent) owns completion — it is the operator proxy and the
# trusted verifier of last resort. Validator subagents return verdicts to
# the main session; the main session marks completed. A subagent's agent_id
# is fixed at spawn and cannot be mutated, so a maker literally cannot call
# TaskUpdate(completed).
set -uo pipefail

# Portability guard (#93): announced fail-open when python3 is missing;
# doctrine-bootstrap.sh names the missing dep once at SessionStart.
if ! command -v python3 >/dev/null 2>&1; then
  echo "[mh:gate] python3 not found — task-complete-separation gate cannot run; allowing (install python3 to restore maker/checker separation)" >&2
  exit 0
fi

# shellcheck disable=SC2016  # single quotes are intentional: this is Python code, not shell
python3 -c '
import json, sys

try:
    d = json.load(sys.stdin)
except Exception as e:
    # Fail-safe = ALLOW. Completion is recoverable; a parse error must not
    # stall all task completion (opposite of the ask-tier gates'"'"' fail-to-ask).
    print(f"[mh:gate] task-complete-separation: unparseable stdin, allowing ({e})", file=sys.stderr)
    sys.exit(0)

if not isinstance(d, dict):
    # A valid-JSON-but-non-object payload (e.g. a bare list) crashed here
    # too, one level above the tool_input guard below (found 2026-08-06).
    print("[mh:gate] task-complete-separation: non-object payload, allowing", file=sys.stderr)
    sys.exit(0)

if d.get("tool_name") != "TaskUpdate":
    sys.exit(0)

# status has no documented key-name alias; read it straight from tool_input.
ti = d.get("tool_input")
if not isinstance(ti, dict):
    # Matches irrecoverable.sh: a malformed
    # tool_input must not crash into an uncaught traceback (found
    # 2026-08-06). This gate is fail-safe=ALLOW by design, so route
    # straight to the same clean exit a missing status already takes,
    # instead of a silent {} fallback that raised AttributeError.
    sys.exit(0)
status = ti.get("status")
if status != "completed":
    sys.exit(0)

# agent_id is present ONLY when the hook fires inside an actual subagent
# call (code.claude.com/docs/en/hooks, confirmed 2026-08-31). agent_type is
# a broader field -- it is ALSO set for a top-level `claude --agent <name>`
# MAIN session, which legitimately owns completion, so keying on agent_type
# alone over-blocked that case (found by security review of the sibling
# agent-recursion-guard.sh gate, 2026-08-31 -- same bug, same fix, here).
agent_id = d.get("agent_id")
if not agent_id:
    sys.exit(0)

agent_type = d.get("agent_type") or "unknown"
print(f"[mh:gate] BLOCKED: subagent ({agent_type}) may not mark its own task completed — "
      f"return to main session for completion (maker≠checker)", file=sys.stderr)
sys.exit(2)
'
exit $?