#!/usr/bin/env bash
# Gate: a subagent may not mark its own task completed (maker≠checker).
# Reads the PreToolUse JSON payload from stdin; exits 2 to block.
#
# Why: the orchestrate validation chain (Builder A → Validator B → …) was
# enforced by prompt doctrine + TaskCreate/addBlockedBy ordering only —
# addBlockedBy gates *ordering*, but nothing computationally stopped the maker
# from marking its own task `completed` without the validator's pass. That is
# the maker-grading-its-own-work circularity the harness exists to forbid.
# Native CC (v2.1.142+) fires PreToolUse inside subagents with `agent_type`
# present (docs-confirmed), so the gate can tell a subagent from the main
# session without an artifact file or an agent_type allowlist.
#
# Rule: deny TaskUpdate(status="completed") whenever `agent_type` is present
# (any subagent). The main session (no `agent_type`) owns completion — it is
# the operator proxy and the trusted verifier of last resort. Validator
# subagents return verdicts to the main session; the main session marks
# completed. A subagent's agent_type is fixed at spawn and cannot be mutated,
# so a maker literally cannot call TaskUpdate(completed).
set -uo pipefail

# Portability guard (#93): announced fail-open when python3 is missing;
# doctrine-bootstrap.sh names the missing dep once at SessionStart.
if ! command -v python3 >/dev/null 2>&1; then
  echo "[kbg:gate] python3 not found — task-complete-separation gate cannot run; allowing (install python3 to restore maker/checker separation)" >&2
  exit 0
fi

# shellcheck disable=SC2016  # single quotes are intentional: this is Python code, not shell
python3 -c '
import json, sys

try:
    d = json.load(sys.stdin)
except Exception as e:
    # Fail-safe = ALLOW. Completion is recoverable; a parse error must not
    # stall all task completion (opposite of verifier-protect'"'"'s fail-to-ask).
    print(f"[kbg:gate] task-complete-separation: unparseable stdin, allowing ({e})", file=sys.stderr)
    sys.exit(0)

if not isinstance(d, dict):
    # A valid-JSON-but-non-object payload (e.g. a bare list) crashed here
    # too, one level above the tool_input guard below (found 2026-08-06).
    print("[kbg:gate] task-complete-separation: non-object payload, allowing", file=sys.stderr)
    sys.exit(0)

if d.get("tool_name") != "TaskUpdate":
    sys.exit(0)

# status has no documented key-name alias; read it straight from tool_input.
ti = d.get("tool_input")
if not isinstance(ti, dict):
    # Matches irrecoverable.sh and verifier-protect.sh: a malformed
    # tool_input must not crash into an uncaught traceback (found
    # 2026-08-06). This gate is fail-safe=ALLOW by design, so route
    # straight to the same clean exit a missing status already takes,
    # instead of a silent {} fallback that raised AttributeError.
    sys.exit(0)
status = ti.get("status")
if status != "completed":
    sys.exit(0)

# agent_type is present only when the hook fires inside a subagent (or a
# --agent session). Absent => main session => allowed.
agent_type = d.get("agent_type")
if not agent_type:
    sys.exit(0)

print(f"[kbg:gate] BLOCKED: subagent ({agent_type}) may not mark its own task completed — "
      f"return to main session for completion (maker≠checker)", file=sys.stderr)
sys.exit(2)
'
exit $?