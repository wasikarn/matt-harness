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

python3 -c "
import json, sys

try:
    d = json.load(sys.stdin)
except Exception as e:
    # Fail-safe = ALLOW. Completion is recoverable; a parse error must not
    # stall all task completion (opposite of verifier-protect's fail-to-ask).
    print(f'[kbg:gate] task-complete-separation: unparseable stdin, allowing ({e})', file=sys.stderr)
    sys.exit(0)

if d.get('tool_name') != 'TaskUpdate':
    sys.exit(0)

# status has no documented key-name alias; read it straight from tool_input.
status = d.get('tool_input', {}).get('status')
if status != 'completed':
    sys.exit(0)

# agent_type is present only when the hook fires inside a subagent (or a
# --agent session). Absent => main session => allowed.
agent_type = d.get('agent_type')
if not agent_type:
    sys.exit(0)

print(f'[kbg:gate] BLOCKED: subagent ({agent_type}) may not mark its own task completed — '
      f'return to main session for completion (maker≠checker)', file=sys.stderr)
sys.exit(2)
"
exit $?