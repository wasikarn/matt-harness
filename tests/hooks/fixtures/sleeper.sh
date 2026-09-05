#!/usr/bin/env bash
# Synthetic PreToolUse gate fixture: hangs past the dispatcher's 8s gate
# timeout so tests/hooks/test-dispatch-pretooluse.sh can assert the timed-out
# gate is killed, counted as allow, and journaled as decision "timeout".
sleep 20
echo '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny"}}'
exit 0
